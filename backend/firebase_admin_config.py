"""Lazy Firebase Admin configuration for future authenticated endpoints."""

import os
from threading import Lock

import firebase_admin
from firebase_admin import credentials


class FirebaseConfigurationError(RuntimeError):
    """Firebase authentication is unavailable because configuration failed."""


_APP_NAME = "study-ai-auth"
_initialization_lock = Lock()


def get_firebase_app():
    """Return the configured app or raise without exposing credential details."""
    project_id = os.getenv("FIREBASE_PROJECT_ID", "").strip()
    if not project_id:
        raise FirebaseConfigurationError("Firebase project configuration is missing.")

    with _initialization_lock:
        try:
            try:
                app = firebase_admin.get_app(_APP_NAME)
            except ValueError:
                credential = credentials.ApplicationDefault()
                google_credential = credential.get_credential()
                credential_project = getattr(google_credential, "project_id", None)
                if credential_project and credential_project != project_id:
                    raise FirebaseConfigurationError("Firebase project configuration does not match.")
                app = firebase_admin.initialize_app(
                    credential, {"projectId": project_id}, name=_APP_NAME
                )

            if app.project_id != project_id:
                raise FirebaseConfigurationError("Firebase project configuration does not match.")
            return app
        except FirebaseConfigurationError:
            raise
        except Exception:
            raise FirebaseConfigurationError("Firebase Admin initialization failed.") from None
