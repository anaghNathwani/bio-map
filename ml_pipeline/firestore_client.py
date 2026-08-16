"""
Shared Firebase Admin SDK init for the ML pipeline scripts. Firestore only —
blob storage (photos/audio/model files) lives in Supabase Storage instead of
Firebase Storage, since Firebase Storage now requires a linked billing
account (Blaze) for every project regardless of usage, and Supabase's free
tier needs no card. See publish_model.py and live_poll.py for the Supabase
(boto3 S3-compatible / plain HTTPS) access this replaces.

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
