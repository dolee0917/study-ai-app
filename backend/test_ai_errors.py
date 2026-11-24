import contextlib
import io
import unittest
from unittest.mock import Mock, patch

from fastapi import HTTPException
from fastapi.testclient import TestClient
from google.genai import errors

from backend.main import QuizRequest, SummaryRequest, app, generate_quiz, summarize, require_firebase_user
from backend.rate_limiter import RateLimiter


class AIErrorTest(unittest.TestCase):
    def setUp(self):
        limiter = patch('backend.main.rate_limiter', RateLimiter())
        limiter.start()
        self.addCleanup(limiter.stop)
        overrides = patch.dict(app.dependency_overrides, {require_firebase_user: lambda: 'test-user'})
        overrides.start()
        self.addCleanup(overrides.stop)
        self.key = patch('backend.main.api_key', 'mock-key')
        self.client = patch('backend.main.genai.Client')
        self.sleep = patch('backend.main.time.sleep')
        self.key.start()
        self.generate = self.client.start().return_value.models.generate_content
        self.sleep.start()
        self.addCleanup(self.key.stop)
        self.addCleanup(self.client.stop)
        self.addCleanup(self.sleep.stop)

    @staticmethod
    def error(code):
        return errors.APIError(code, {'error': {'code': code, 'message': 'PRIVATE_SECRET'}})

    def test_gemini_codes_are_classified_on_both_endpoints(self):
        cases = [(429, 429, 'AI_RATE_LIMIT'), (404, 502, 'AI_MODEL_NOT_FOUND'),
                 (401, 502, 'AI_AUTH_ERROR'), (403, 502, 'AI_AUTH_ERROR')]
        for endpoint, request in [(summarize, SummaryRequest(text='test input long enough')),
                                  (generate_quiz, QuizRequest(text='test input long enough'))]:
            for upstream, status, code in cases:
                with self.subTest(endpoint=endpoint.__name__, upstream=upstream):
                    self.generate.reset_mock()
                    self.generate.side_effect = self.error(upstream)
                    logs = io.StringIO()
                    with contextlib.redirect_stdout(logs), self.assertRaises(HTTPException) as raised:
                        endpoint(request)
                    self.assertEqual((raised.exception.status_code, raised.exception.code), (status, code))
                    self.assertEqual(self.generate.call_count, 1)
                    self.assertNotIn('PRIVATE_SECRET', logs.getvalue())

    def test_final_503_and_fallback_failure_use_final_error(self):
        self.generate.side_effect = [self.error(503)] * 4 + [self.error(429)]
        with self.assertRaises(HTTPException) as raised:
            summarize(SummaryRequest(text='test input long enough'))
        self.assertEqual((raised.exception.status_code, raised.exception.code), (429, 'AI_RATE_LIMIT'))
        self.assertEqual(self.generate.call_count, 5)
        self.generate.reset_mock()
        self.generate.side_effect = self.error(503)
        with self.assertRaises(HTTPException) as raised:
            generate_quiz(QuizRequest(text='test input long enough'))
        self.assertEqual((raised.exception.status_code, raised.exception.code), (503, 'AI_UNAVAILABLE'))
        self.assertEqual(self.generate.call_count, 4)

    def test_empty_invalid_and_unknown(self):
        cases = [('', 'AI_EMPTY_RESPONSE'), ('not-json', 'AI_INVALID_RESPONSE'),
                 ('{"questions": {}}', 'AI_INVALID_RESPONSE')]
        for body, code in cases:
            with self.subTest(body=body):
                self.generate.side_effect = None
                self.generate.return_value = Mock(text=body)
                with self.assertRaises(HTTPException) as raised:
                    generate_quiz(QuizRequest(text='test input long enough'))
                self.assertEqual(raised.exception.code, code)
        self.generate.side_effect = RuntimeError('PRIVATE_SECRET')
        logs = io.StringIO()
        with contextlib.redirect_stdout(logs), self.assertRaises(HTTPException) as raised:
            summarize(SummaryRequest(text='test input long enough'))
        self.assertEqual(raised.exception.code, 'AI_UNKNOWN_ERROR')
        self.assertNotIn('PRIVATE_SECRET', logs.getvalue())

    def test_http_error_shape_and_framework_errors(self):
        with TestClient(app) as http:
            with patch('backend.main.api_key', None):
                for path in ['/summarize', '/generate-quiz']:
                    response = http.post(path, json={'text': 'test input long enough'})
                    self.assertEqual(response.status_code, 500)
                    self.assertEqual(response.json()['code'], 'AI_CONFIG_ERROR')
                    self.assertIsInstance(response.json()['detail'], str)
            self.assertEqual(http.post('/summarize', json={'text': 'x'}).status_code, 422)
            self.assertNotIn('code', http.get('/missing-route').json())


if __name__ == '__main__':
    unittest.main()
