"""
Verifies Firebase ID tokens for the media upload broker (app/api/media.py).

Independent of this backend's own JWT auth (app/services/auth.py,
app/api/deps.py), which authenticates against this backend's own Postgres
`users` table for the separate legacy auth/sightings/annotations/leaderboard
system. The live app's real users/sessions are Firebase Auth accounts, so the
media broker verifies those tokens directly instead.
"""
import json
import logging

import firebase_admin
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from firebase_admin import auth as firebase_auth_sdk
from firebase_admin import credentials

from app.config import settings

logger = logging.getLogger(__name__)
bearer = HTTPBearer()

_app: firebase_admin.App | None = None


def _get_app() -> firebase_admin.App:
    global _app
    if _app is not None:
        return _app
    if settings.firebase_service_account_json:
        cred = credentials.Certificate(json.loads(settings.firebase_service_account_json))
    else:
        # Falls back to Application Default Credentials if no key is configured
        # (e.g. GOOGLE_APPLICATION_CREDENTIALS set in the environment).
        cred = credentials.ApplicationDefault()
    _app = firebase_admin.initialize_app(cred, name="media-broker")
    return _app


async def firebase_user_id(
    creds: HTTPAuthorizationCredentials = Depends(bearer),
) -> str:
    """FastAPI dependency: verifies a Firebase ID token and returns the caller's uid."""
    try:
        decoded = firebase_auth_sdk.verify_id_token(creds.credentials, app=_get_app())
        return decoded["uid"]
    except Exception as e:
        logger.warning("Firebase token verification failed: %s", e)
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid Firebase token")
