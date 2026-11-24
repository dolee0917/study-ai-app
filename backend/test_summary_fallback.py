import json
import unittest
from unittest.mock import Mock, call, patch

from fastapi import HTTPException
from google.genai import errors

from backend.main import QuizRequest, SummaryRequest, generate_quiz, summarize


class SummaryFallbackTest(unittest.TestCase):
    @staticmethod
    def api_error(code):
        return errors.APIError(code, {"error": {"code": code}})

    def setUp(self):
        self.key_patch = patch("backend.main.api_key", "mock-key")
        self.client_patch = patch("backend.main.genai.Client")
        self.sleep_patch = patch("backend.main.time.sleep")
        self.key_patch.start()
        self.client = self.client_patch.start()
        self.sleep = self.sleep_patch.start()
        self.addCleanup(self.key_patch.stop)
        self.addCleanup(self.client_patch.stop)
        self.addCleanup(self.sleep_patch.stop)
        self.generate = self.client.return_value.models.generate_content
        self.request = SummaryRequest(text="테스트를 위한 강의 자료 내용입니다.")

    def test_primary_success_does_not_call_fallback(self):
        self.generate.return_value = Mock(text="요약")
        self.assertEqual(summarize(self.request), {"summary": "요약"})
        self.assertEqual(self.generate.call_count, 1)
        self.assertEqual(self.generate.call_args.kwargs["model"], "gemini-3.8-flash")
        self.sleep.assert_not_called()

    def test_primary_503_then_success_does_not_call_fallback(self):
        self.generate.side_effect = [self.api_error(503), Mock(text="요약")]
        self.assertEqual(summarize(self.request), {"summary": "요약"})
        self.assertEqual(self.generate.call_count, 2)
        self.assertTrue(all(c.kwargs["model"] == "gemini-3.8-flash"
                            for c in self.generate.call_args_list))
        self.sleep.assert_called_once_with(2)

    def test_exhausted_503_falls_back_once_with_same_prompt_and_settings(self):
        self.generate.side_effect = [self.api_error(503) for _ in range(4)] + [Mock(text="대체 요약")]
        self.assertEqual(summarize(self.request), {"summary": "대체 요약"})
        self.assertEqual(self.generate.call_count, 5)
        calls = self.generate.call_args_list
        self.assertEqual([c.kwargs["model"] for c in calls],
                         ["gemini-3.8-flash"] * 4 + ["gemini-3.5-flash-lite"])
        self.assertEqual({k: v for k, v in calls[0].kwargs.items() if k != "model"},
                         {k: v for k, v in calls[-1].kwargs.items() if k != "model"})
        self.assertEqual(self.sleep.call_args_list, [call(2), call(4), call(8)])

    def test_fallback_failure_is_not_retried_and_returns_existing_error(self):
        self.generate.side_effect = [self.api_error(503) for _ in range(5)]
        with self.assertRaises(HTTPException) as raised:
            summarize(self.request)
        self.assertEqual(raised.exception.status_code, 503)
        self.assertEqual(raised.exception.code, "AI_UNAVAILABLE")
        self.assertEqual(self.generate.call_count, 5)
        self.assertEqual(self.sleep.call_args_list, [call(2), call(4), call(8)])

    def test_non_503_errors_do_not_fallback(self):
        for error, status, code in [(self.api_error(404), 502, "AI_MODEL_NOT_FOUND"),
                                    (self.api_error(429), 429, "AI_RATE_LIMIT"),
                                    (self.api_error(401), 502, "AI_AUTH_ERROR"),
                                    (RuntimeError("failure"), 502, "AI_UNKNOWN_ERROR")]:
            with self.subTest(error=type(error).__name__):
                self.generate.reset_mock()
                self.sleep.reset_mock()
                self.generate.side_effect = error
                with self.assertRaises(HTTPException) as raised:
                    summarize(self.request)
                self.assertEqual(raised.exception.status_code, status)
                self.assertEqual(raised.exception.code, code)
                self.assertEqual(self.generate.call_count, 1)
                self.assertEqual(self.generate.call_args.kwargs["model"], "gemini-3.8-flash")
                self.sleep.assert_not_called()

    def test_empty_primary_response_does_not_fallback(self):
        self.generate.return_value = Mock(text="")
        with self.assertRaises(HTTPException) as raised:
            summarize(self.request)
        self.assertEqual(raised.exception.status_code, 502)
        self.assertEqual(raised.exception.code, "AI_EMPTY_RESPONSE")
        self.assertEqual(self.generate.call_count, 1)
        self.sleep.assert_not_called()

    def test_empty_fallback_response_returns_existing_empty_response_error(self):
        self.generate.side_effect = [self.api_error(503) for _ in range(4)] + [Mock(text="")]
        with self.assertRaises(HTTPException) as raised:
            summarize(self.request)
        self.assertEqual(raised.exception.status_code, 502)
        self.assertEqual(raised.exception.code, "AI_EMPTY_RESPONSE")
        self.assertEqual(self.generate.call_count, 5)

    def test_quiz_keeps_existing_retry_policy_and_model(self):
        self.generate.side_effect = [self.api_error(503), Mock(text=json.dumps({"questions": []}))]
        self.assertEqual(generate_quiz(QuizRequest(text="테스트를 위한 강의 자료 내용입니다.")),
                         {"questions": []})
        self.assertEqual(self.generate.call_count, 2)
        self.assertTrue(all(c.kwargs["model"] == "gemini-3.5-flash-lite"
                            for c in self.generate.call_args_list))
        self.assertTrue(all(c.kwargs["config"] == {"response_mime_type": "application/json"}
                            for c in self.generate.call_args_list))
        self.sleep.assert_called_once_with(2)


if __name__ == "__main__":
    unittest.main()
