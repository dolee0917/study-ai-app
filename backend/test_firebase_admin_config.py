import unittest
from types import SimpleNamespace
from unittest.mock import patch

import firebase_admin_config as config


class FirebaseAdminConfigurationTests(unittest.TestCase):
    @patch.dict("os.environ", {}, clear=True)
    def test_missing_project_fails_without_initializing(self):
        with patch.object(config.firebase_admin, "initialize_app") as initialize:
            with self.assertRaises(config.FirebaseConfigurationError):
                config.get_firebase_app()
            initialize.assert_not_called()

    @patch.dict("os.environ", {"FIREBASE_PROJECT_ID": "test-project"}, clear=True)
    def test_initializes_once_and_reuses_matching_app(self):
        app = SimpleNamespace(project_id="test-project")
        credential = unittest.mock.Mock()
        credential.get_credential.return_value = SimpleNamespace(project_id="test-project")
        with patch.object(config.firebase_admin, "get_app", side_effect=[ValueError(), app]), \
                patch.object(config.credentials, "ApplicationDefault", return_value=credential), \
                patch.object(config.firebase_admin, "initialize_app", return_value=app) as initialize:
            self.assertIs(config.get_firebase_app(), app)
            self.assertIs(config.get_firebase_app(), app)
            initialize.assert_called_once_with(
                credential, {"projectId": "test-project"}, name="study-ai-auth"
            )

    @patch.dict("os.environ", {"FIREBASE_PROJECT_ID": "test-project"}, clear=True)
    def test_invalid_credentials_do_not_expose_error_details(self):
        with patch.object(config.firebase_admin, "get_app", side_effect=ValueError()), \
                patch.object(config.credentials, "ApplicationDefault", side_effect=ValueError("secret")):
            with self.assertRaises(config.FirebaseConfigurationError) as error:
                config.get_firebase_app()
            self.assertNotIn("secret", str(error.exception))
            self.assertIsNone(error.exception.__cause__)

    @patch.dict("os.environ", {"FIREBASE_PROJECT_ID": "test-project"}, clear=True)
    def test_mismatched_credential_or_existing_app_fails_closed(self):
        credential = unittest.mock.Mock()
        credential.get_credential.return_value = SimpleNamespace(project_id="other-project")
        with patch.object(config.firebase_admin, "get_app", side_effect=ValueError()), \
                patch.object(config.credentials, "ApplicationDefault", return_value=credential), \
                patch.object(config.firebase_admin, "initialize_app") as initialize:
            with self.assertRaises(config.FirebaseConfigurationError):
                config.get_firebase_app()
            initialize.assert_not_called()
        with patch.object(config.firebase_admin, "get_app", return_value=SimpleNamespace(project_id="other-project")):
            with self.assertRaises(config.FirebaseConfigurationError):
                config.get_firebase_app()


if __name__ == "__main__":
    unittest.main()
