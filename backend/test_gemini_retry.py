import unittest
from unittest.mock import Mock, call, patch

from google.genai import errors

from backend.main import call_gemini_with_retry


class GeminiRetryTest(unittest.TestCase):
    @staticmethod
    def api_error(code):
        return errors.APIError(code, {"error": {"code": code}})

    @patch("backend.main.time.sleep")
    def test_success_without_retry(self, sleep):
        request = Mock(return_value="response")

        self.assertEqual(call_gemini_with_retry(request, model="model"), "response")
        request.assert_called_once_with(model="model")
        sleep.assert_not_called()

    @patch("backend.main.time.sleep")
    def test_503_then_success(self, sleep):
        request = Mock(side_effect=[self.api_error(503), "response"])

        self.assertEqual(call_gemini_with_retry(request), "response")
        self.assertEqual(request.call_count, 2)
        sleep.assert_called_once_with(2)

    @patch("backend.main.time.sleep")
    def test_repeated_503_raises_after_three_retries(self, sleep):
        error = self.api_error(503)
        request = Mock(side_effect=error)

        with self.assertRaises(errors.APIError) as raised:
            call_gemini_with_retry(request)
        self.assertIs(raised.exception, error)
        self.assertEqual(request.call_count, 4)
        self.assertEqual(sleep.call_args_list, [call(2), call(4), call(8)])

    @patch("backend.main.time.sleep")
    def test_404_raises_without_retry(self, sleep):
        error = self.api_error(404)
        request = Mock(side_effect=error)

        with self.assertRaises(errors.APIError) as raised:
            call_gemini_with_retry(request)
        self.assertIs(raised.exception, error)
        request.assert_called_once_with()
        sleep.assert_not_called()


if __name__ == "__main__":
    unittest.main()
