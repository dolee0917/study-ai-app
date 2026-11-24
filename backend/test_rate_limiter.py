import json
import threading
import unittest
from concurrent.futures import ThreadPoolExecutor
from unittest.mock import Mock, patch

from fastapi.testclient import TestClient
from firebase_admin import auth
from google.genai import errors

from backend import firebase_auth, main
from backend.rate_limiter import RateLimitExceeded, RateLimiter


class FakeClock:
    def __init__(self):
        self.now = 0.0

    def __call__(self):
        return self.now


class RateLimiterTests(unittest.TestCase):
    def setUp(self):
        self.clock = FakeClock()
        self.limiter = RateLimiter(clock=self.clock)

    def test_feature_limits_are_separate_and_users_are_independent(self):
        for _ in range(3):
            self.limiter.check_and_record("a", "summary")
        with self.assertRaises(RateLimitExceeded) as error:
            self.limiter.check_and_record("a", "summary")
        self.assertEqual(error.exception.retry_after, 60)
        for _ in range(5):
            self.limiter.check_and_record("a", "quiz")
        with self.assertRaises(RateLimitExceeded):
            self.limiter.check_and_record("a", "quiz")
        self.limiter.check_and_record("b", "summary")
        self.assertEqual(len(self.limiter._users["a"]), 8)
        self.assertEqual(len(self.limiter._users["b"]), 1)
        self.clock.now = 60
        self.limiter.check_and_record("a", "summary")

    def test_daily_limit_combines_features_and_expires_on_rolling_boundary(self):
        limiter = RateLimiter(summary_limit=100, quiz_limit=100, clock=self.clock)
        for i in range(50):
            limiter.check_and_record("a", "summary" if i % 2 else "quiz")
        with self.assertRaises(RateLimitExceeded) as error:
            limiter.check_and_record("a", "quiz")
        self.assertEqual(error.exception.retry_after, 86400)
        self.assertEqual(len(limiter._users["a"]), 50)
        self.clock.now = 86400
        limiter.check_and_record("a", "summary")
        self.assertEqual(len(limiter._users["a"]), 1)

    def test_expired_records_for_inactive_users_are_removed(self):
        self.limiter.check_and_record("inactive", "quiz")
        self.clock.now = 86400
        self.limiter.check_and_record("active", "summary")
        self.assertNotIn("inactive", self.limiter._users)

    def test_invalid_environment_never_disables_limits(self):
        name = "RATE_LIMIT_SUMMARY_PER_MINUTE"
        for value in ("", "0", "-1", "abc", "2.5", "1000001", "１２"):
            with self.subTest(value=value), patch.dict("os.environ", {name: value}, clear=True):
                with self.assertRaises(ValueError):
                    RateLimiter.from_env()
        with patch.dict("os.environ", {
            name: "2", "RATE_LIMIT_QUIZ_PER_MINUTE": "4", "RATE_LIMIT_AI_PER_DAY": "8"
        }, clear=True):
            configured = RateLimiter.from_env()
            self.assertEqual(configured._limits, {"summary": 2, "quiz": 4})
            self.assertEqual(configured._daily_limit, 8)

    def test_concurrent_check_and_record_is_atomic(self):
        barrier = threading.Barrier(20)

        def request():
            barrier.wait()
            try:
                self.limiter.check_and_record("same-user", "summary")
                return True
            except RateLimitExceeded:
                return False

        with ThreadPoolExecutor(max_workers=20) as executor:
            results = list(executor.map(lambda _: request(), range(20)))
        self.assertEqual(sum(results), 3)
        self.assertEqual(len(self.limiter._users["same-user"]), 3)


class RateLimitEndpointTests(unittest.TestCase):
    def setUp(self):
        self.clock = FakeClock()
        self.limiter = RateLimiter(clock=self.clock)
        patches = [
            patch.object(main, "rate_limiter", self.limiter),
            patch.object(main, "api_key", "test-key"),
            patch.object(main.genai, "Client"),
            patch.object(firebase_auth, "get_firebase_app", return_value=object()),
            patch.object(firebase_auth.auth, "verify_id_token", return_value={"uid": "alice"}),
            patch.object(main.time, "sleep"),
        ]
        values = [p.start() for p in patches]
        for p in patches:
            self.addCleanup(p.stop)
        self.gemini = values[2]
        self.verify = values[4]
        self.client = TestClient(main.app)
        self.addCleanup(self.client.close)
        self.payload = {"text": "test input long enough"}
        self.headers = {"Authorization": "Bearer test-token"}

    def post(self, path):
        return self.client.post(path, json=self.payload, headers=self.headers)

    def test_limited_requests_do_not_call_gemini_and_health_is_unlimited(self):
        self.gemini.return_value.models.generate_content.return_value = Mock(text="summary")
        for _ in range(3):
            self.assertEqual(self.post("/summarize").status_code, 200)
        response = self.post("/summarize")
        self.assertEqual(response.status_code, 429)
        self.assertEqual(response.json()["code"], "USER_RATE_LIMIT")
        self.assertEqual(response.headers["retry-after"], "60")
        self.assertEqual(self.gemini.call_count, 3)
        self.assertEqual(len(self.limiter._users["alice"]), 3)
        self.assertEqual(self.client.get("/").status_code, 200)
        self.assertEqual(len(self.limiter._users["alice"]), 3)

    def test_unauthenticated_requests_do_not_consume_quota(self):
        self.assertEqual(self.client.post("/summarize", json=self.payload).status_code, 401)
        self.verify.side_effect = auth.InvalidIdTokenError("invalid")
        self.assertEqual(self.post("/generate-quiz").status_code, 401)
        self.assertEqual(self.limiter._users, {})
        self.gemini.assert_not_called()

    def test_retries_count_once_and_gemini_429_has_distinct_code(self):
        generate = self.gemini.return_value.models.generate_content
        unavailable = errors.APIError(503, {"error": {"code": 503}})
        generate.side_effect = [unavailable, Mock(text=json.dumps({"questions": []}))]
        self.assertEqual(self.post("/generate-quiz").status_code, 200)
        self.assertEqual(generate.call_count, 2)
        self.assertEqual(len(self.limiter._users["alice"]), 1)
        generate.side_effect = errors.APIError(429, {"error": {"code": 429}})
        response = self.post("/generate-quiz")
        self.assertEqual(response.status_code, 429)
        self.assertEqual(response.json()["code"], "AI_RATE_LIMIT")
        self.assertEqual(len(self.limiter._users["alice"]), 2)


if __name__ == "__main__":
    unittest.main()
