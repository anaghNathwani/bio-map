#!/usr/bin/env bash
# BirdMap deployment script
# Deploys:
#   1. Firestore rules + indexes → Firebase
#   2. Firebase Hosting (web map) → Firebase
#   3. FastAPI backend (Vision API + Bird Info proxy) → Fly.io
#
# Prerequisites:
#   firebase-tools:  npm install -g firebase-tools && firebase login
#   flyctl:          brew install flyctl && fly auth login
#   Node + npm:      for web build
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
FIREBASE_ROOT="$(dirname "$REPO_ROOT")"   # firebase.json lives one level up
WEB_DIR="$REPO_ROOT/web"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info() { echo -e "${GREEN}==>${NC} $*"; }
warn() { echo -e "${YELLOW}WARN:${NC} $*"; }

# ── 1. Build web app ──────────────────────────────────────────────────────────
if [ ! -f "$WEB_DIR/.env.local" ]; then
  warn "No web/.env.local found. Copy web/.env.example → web/.env.local and fill in Firebase config."
  warn "Skipping web build — Firestore rules/indexes will still deploy."
  SKIP_WEB=1
else
  info "Building web app..."
  cd "$WEB_DIR"
  npm ci --silent
  npm run build
  cd "$REPO_ROOT"
  SKIP_WEB=0
fi

# ── 2. Deploy to Firebase ─────────────────────────────────────────────────────
info "Deploying to Firebase..."
cd "$FIREBASE_ROOT"
if [ "${SKIP_WEB:-0}" = "0" ]; then
  firebase deploy --only firestore,hosting
else
  firebase deploy --only firestore
fi
cd "$REPO_ROOT"

# ── 3. Deploy backend to Fly.io ───────────────────────────────────────────────
info "Deploying backend to Fly.io..."
if ! command -v fly &>/dev/null; then
  warn "flyctl not found. Install: brew install flyctl && fly auth login"
  warn "Skipping backend deploy."
else
  if ! fly status --app birdmap-api &>/dev/null 2>&1; then
    info "Creating Fly.io app 'birdmap-api'..."
    fly apps create birdmap-api
    echo ""
    warn "Set required secrets before first deploy:"
    echo "  fly secrets set --app birdmap-api \\"
    echo "    DATABASE_URL='postgresql+asyncpg://...' \\"
    echo "    SECRET_KEY='$(python3 -c "import secrets; print(secrets.token_hex(32))")' \\"
    echo "    S3_ENDPOINT='...' S3_ACCESS_KEY='...' S3_SECRET_KEY='...'"
    echo ""
    echo "Then re-run this script."
    exit 0
  fi

  fly deploy --app birdmap-api --dockerfile backend/Dockerfile --build-target production
  info "Backend live at: https://birdmap-api.fly.dev"
fi

echo ""
info "Deployment complete!"
echo "  Web map:  $(cd "$FIREBASE_ROOT" && firebase hosting:channel:list 2>/dev/null | grep 'live' | awk '{print $2}' || echo '<firebase hosting URL>')"
echo "  API:      https://birdmap-api.fly.dev"
echo ""
if [ -z "$(fly secrets list --app birdmap-api 2>/dev/null | grep GOOGLE_CLOUD_API_KEY || true)" ]; then
  warn "Google Vision not configured. Set: fly secrets set --app birdmap-api GOOGLE_CLOUD_API_KEY=<key>"
fi
echo "  Tonight: upgrade Firebase to Blaze → Firebase Console → Billing → Upgrade"
echo "  This enables Firebase Storage quota for photo/audio uploads from the iOS app."
