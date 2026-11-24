import threading
import unittest
from unittest.mock import patch

from fastapi import Depends, FastAPI
from fastapi.testclient import TestClient
from firebase_admin import auth, exceptions
from google.auth.exceptions import TransportError

import firebase_auth as module
from firebase_admin_config import FirebaseConfigurationError


app = FastAPI()
app.add_exception_handler(module.FirebaseAuthError, module.firebase_auth_error_handler)


@app.get("/protected")
async def protected(uid: str = Depends(module.require_firebase_user)):
    return {"uid": uid, "event_loop_thread": threading.get_ident()}


class FirebaseAuthTests(unittest.TestCase):
    def setUp(self):
        self.client = TestClient(app)
        self.addCleanup(self.client.close)

    def assert_auth_error(self, response, status, code):
        self.assertEqual(response.status_code, status)
        self.assertEqual(response.json()["code"], code)
        self.assertIsInstance(response.json()["detail"], str)
        self.assertNotIn("secret", response.text)
        if status == 401:
            self.assertEqual(response.headers["www-authenticate"], "Bearer")

    def test_valid_token_returns_verified_uid_in_worker_thread(self):
        marker = object()
        worker_ids = []

        def verify(token, *, app, check_revoked):
            worker_ids.append(threading.get_ident())
            self.assertEqual(token, "test-token")
            self.assertIs(app, marker)
            self.assertFalse(check_revoked)
            return {"uid": "verified-user"}

        with patch.object(module, "get_firebase_app", return_value=marker), \
                patch.object(module.auth, "verify_id_token", side_effect=verify):
            response = self.client.get("/protected?uid=attacker", headers={"Authorization": "Bearer test-token"})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["uid"], "verified-user")
        self.assertNotEqual(worker_ids[0], response.json()["event_loop_thread"])

    def test_missing_header_and_bad_bearer_formats(self):
        with patch.object(module, "get_firebase_app") as initialize:
            self.assert_auth_error(self.client.get("/protected"), 401, "AUTH_MISSING")
            for value in ("", "Basic abc", "Bearer", "Bearer ", "Bearer two tokens"):
                with self.subTest(value=value):
                    response = self.client.get("/protected", headers={"Authorization": value})
                    self.assert_auth_error(response, 401, "AUTH_INVALID_FORMAT")
            initialize.assert_not_called()

    def test_invalid_expired_and_wrong_project_tokens(self):
        cases = [
            (auth.InvalidIdTokenError("secret invalid"), "AUTH_TOKEN_INVALID"),
            (auth.ExpiredIdTokenError("secret expired", None), "AUTH_TOKEN_EXPIRED"),
            (auth.InvalidIdTokenError("secret wrong project audience"), "AUTH_TOKEN_INVALID"),
        ]
        for error, code in cases:
            with self.subTest(code=code, error=type(error).__name__), \
                    patch.object(module, "get_firebase_app", return_value=object()), \
                    patch.object(module.auth, "verify_id_token", side_effect=error):
                response = self.client.get("/protected", headers={"Authorization": "Bearer token"})
                self.assert_auth_error(response, 401, code)

    def test_missing_or_invalid_uid_is_rejected(self):
        for claims in ({}, {"uid": None}, {"uid": " "}, {"uid": 42}, {"uid": "x" * 129}, None):
            with self.subTest(claims=claims), \
                    patch.object(module, "get_firebase_app", return_value=object()), \
                    patch.object(module.auth, "verify_id_token", return_value=claims):
                self.assert_auth_error(
                    self.client.get("/protected", headers={"Authorization": "Bearer token"}),
                    401, "AUTH_TOKEN_INVALID",
                )

    def test_configuration_failure_is_unavailable(self):
        with patch.object(module, "get_firebase_app", side_effect=FirebaseConfigurationError("secret")), \
                patch.object(module.auth, "verify_id_token") as verify:
            self.assert_auth_error(
                self.client.get("/protected", headers={"Authorization": "Bearer token"}),
                503, "AUTH_CONFIG_ERROR",
            )
            verify.assert_not_called()

    def test_certificate_transport_and_unexpected_errors_fail_closed(self):
        cases = [
            auth.CertificateFetchError("secret cert", None),
            TransportError("secret network"),
            exceptions.UnavailableError("secret unavailable"),
            RuntimeError("secret unexpected"),
        ]
        for error in cases:
            with self.subTest(error=type(error).__name__), \
                    patch.object(module, "get_firebase_app", return_value=object()), \
                    patch.object(module.auth, "verify_id_token", side_effect=error):
                self.assert_auth_error(
                    self.client.get("/protected", headers={"Authorization": "Bearer token"}),
                    503, "AUTH_UNAVAILABLE",
                )


if __name__ == "__main__":
    unittest.main()
