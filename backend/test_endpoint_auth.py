import json
import unittest
from unittest.mock import Mock, patch

from fastapi.testclient import TestClient
from firebase_admin import auth
from google.genai import errors

from backend import firebase_auth, main
from backend.firebase_admin_config import FirebaseConfigurationError
from backend.rate_limiter import RateLimiter


class EndpointAuthenticationTests(unittest.TestCase):
    def setUp(self):
        limiter = patch.object(main, "rate_limiter", RateLimiter())
        limiter.start()
        self.addCleanup(limiter.stop)
        self.client = TestClient(main.app)
        self.addCleanup(self.client.close)
        self.key = patch.object(main, "api_key", "test-key")
        self.key.start()
        self.addCleanup(self.key.stop)
        self.gemini = patch.object(main.genai, "Client")
        self.gemini_client = self.gemini.start()
        self.addCleanup(self.gemini.stop)
        self.payload = {"text": "test study content with sufficient length"}

    def request(self, path, authorization=None):
        headers = {} if authorization is None else {"Authorization": authorization}
        return self.client.post(path, headers=headers, json=self.payload)

    def assert_denied(self, response, status, code):
        self.assertEqual(response.status_code, status)
        self.assertEqual(set(response.json()), {"detail", "code"})
        self.assertEqual(response.json()["code"], code)
        if status == 401:
            self.assertEqual(response.headers["www-authenticate"], "Bearer")
        self.gemini_client.assert_not_called()

    def test_missing_authorization_blocks_both_endpoints_before_gemini(self):
        with patch.object(firebase_auth, "get_firebase_app") as initialize:
            for path in ("/summarize", "/generate-quiz"):
                with self.subTest(path=path):
                    self.assert_denied(self.request(path), 401, "AUTH_MISSING")
            initialize.assert_not_called()

    def test_invalid_expired_and_malformed_tokens_block_both_endpoints(self):
        cases = [
            ("Bearer invalid", auth.InvalidIdTokenError("invalid"), "AUTH_TOKEN_INVALID"),
            ("Bearer expired", auth.ExpiredIdTokenError("expired", None), "AUTH_TOKEN_EXPIRED"),
        ]
        with patch.object(firebase_auth, "get_firebase_app", return_value=object()):
            for path in ("/summarize", "/generate-quiz"):
                self.assert_denied(self.request(path, "Basic x"), 401, "AUTH_INVALID_FORMAT")
                for header, error, code in cases:
                    with self.subTest(path=path, code=code), \
                            patch.object(firebase_auth.auth, "verify_id_token", side_effect=error):
                        self.assert_denied(self.request(path, header), 401, code)

    def test_valid_token_allows_both_endpoints(self):
        generate = self.gemini_client.return_value.models.generate_content
        generate.side_effect = [Mock(text="summary"), Mock(text=json.dumps({"questions": []}))]
        with patch.object(firebase_auth, "get_firebase_app", return_value=object()), \
                patch.object(firebase_auth.auth, "verify_id_token", return_value={"uid": "verified-user"}) as verify:
            summary = self.request("/summarize", "Bearer valid")
            quiz = self.request("/generate-quiz", "Bearer valid")
        self.assertEqual(summary.status_code, 200)
        self.assertEqual(summary.json(), {"summary": "summary"})
        self.assertEqual(quiz.status_code, 200)
        self.assertEqual(quiz.json(), {"questions": []})
        self.assertEqual(verify.call_count, 2)
        self.assertEqual(generate.call_count, 2)

    def test_configuration_and_certificate_failure_block_both_endpoints(self):
        for path in ("/summarize", "/generate-quiz"):
            with self.subTest(path=path, failure="configuration"), \
                    patch.object(firebase_auth, "get_firebase_app", side_effect=FirebaseConfigurationError("private")):
                self.assert_denied(self.request(path, "Bearer valid"), 503, "AUTH_CONFIG_ERROR")
            with self.subTest(path=path, failure="certificate"), \
                    patch.object(firebase_auth, "get_firebase_app", return_value=object()), \
                    patch.object(firebase_auth.auth, "verify_id_token", side_effect=auth.CertificateFetchError("private", None)):
                self.assert_denied(self.request(path, "Bearer valid"), 503, "AUTH_UNAVAILABLE")

    def test_health_is_public_and_does_not_call_firebase_or_gemini(self):
        with patch.object(firebase_auth, "get_firebase_app") as initialize, \
                patch.object(firebase_auth.auth, "verify_id_token") as verify:
            response = self.client.get("/")
        self.assertEqual(response.status_code, 200)
        initialize.assert_not_called()
        verify.assert_not_called()
        self.gemini_client.assert_not_called()

    def test_authenticated_gemini_error_preserves_existing_response(self):
        self.gemini_client.return_value.models.generate_content.side_effect = errors.APIError(
            429, {"error": {"code": 429, "message": "private"}}
        )
        with patch.object(firebase_auth, "get_firebase_app", return_value=object()), \
                patch.object(firebase_auth.auth, "verify_id_token", return_value={"uid": "verified-user"}):
            for path in ("/summarize", "/generate-quiz"):
                with self.subTest(path=path):
                    response = self.request(path, "Bearer valid")
                    self.assertEqual(response.status_code, 429)
                    self.assertEqual(set(response.json()), {"detail", "code"})
                    self.assertEqual(response.json()["code"], "AI_RATE_LIMIT")
                    self.assertNotIn("private", response.text)


if __name__ == "__main__":
    unittest.main()
