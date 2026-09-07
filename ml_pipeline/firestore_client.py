"""
Shared Firebase Admin SDK init for the ML pipeline scripts. Firestore only —
no Firebase Storage (which needs a linked Blaze billing account for any
usage) and no third-party storage either. Sighting photo/audio and model
blobs are all embedded directly as base64 in Firestore documents instead
(chunked across a subcollection for the model, which is too large for one
document) — see publish_model.py and live_poll.py.

Credentials are resolved in this order:
  1. --service-account <path-to-json> (explicit)
  2. GOOGLE_APPLICATION_CREDENTIALS env var (explicit)
  3. Application Default Credentials — e.g. `gcloud auth application-default login`,
     or the ambient credentials of a machine already authenticated to the
     birdmap-citizenscience GCP project.

Get a service account key from: Firebase Console -> Project Settings ->
Service Accounts -> Generate new private key.
"""

import os

import firebase_admin
from firebase_admin import credentials, firestore

PROJECT_ID = "birdmap-citizenscience"

_app: firebase_admin.App | None = None


def init_app(service_account_path: str | None = None) -> firebase_admin.App:
    """Idempotently initialise the default Firebase Admin app."""
    global _app
    if _app is not None:
        return _app

    path = service_account_path or os.environ.get("GOOGLE_APPLICATION_CREDENTIALS")
    if path:
        cred = credentials.Certificate(path)
    else:
        cred = credentials.ApplicationDefault()

    _app = firebase_admin.initialize_app(cred, {"projectId": PROJECT_ID})
    return _app


def get_db(service_account_path: str | None = None):
    init_app(service_account_path)
    return firestore.client()
