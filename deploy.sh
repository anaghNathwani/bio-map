#!/usr/bin/env bash
# BirdMap deployment script — Render compute target.
# Deploys:
#   1. Firestore rules + indexes -> Firebase (free, Spark plan — unaffected by
#      the Storage/Blaze requirement, which only gates Firebase *Storage*)
#   2. Firebase Hosting (web map) -> Firebase
#   3. Backend (media upload broker + legacy Postgres API) -> Render, backed
#      by Supabase (Postgres + S3-compatible Storage) — all free, no card
#      required for Supabase; Render currently requires a card on file even
#      on its free plan (confirmed live, contrary to its own docs) — see
#      docs/DEPLOYMENT.md. For compute targets that don't need a personal
#      card, see deploy-gcp.sh (Cloud Run) or deploy-selfhost.sh (your own
#      machine) — same Supabase data layer either way. All three are safe to
#      keep configured at once.
#
# Prerequisites (one-time, needs your browser — this script can't do these for you):
#   firebase-tools:  npm install -g firebase-tools && firebase login
#   supabase CLI:    brew install supabase/tap/supabase && supabase login
#   render CLI:      brew install render && render login
#   Node + npm:      for the web build
#
# Also needs a Firebase service account key for the backend + GitHub Actions
# live-poll workflow to authenticate as an admin (Firebase Console -> Project
# Settings -> Service Accounts -> Generate new private key). Pass its path as
# the first argument, or place it at ./firebase-service-account.json.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
FIREBASE_ROOT="$REPO_ROOT"   # firebase.json/.firebaserc live at the repo root, versioned
WEB_DIR="$REPO_ROOT/web"
APP_NAME="birdmap-api"
SUPABASE_PROJECT_NAME="birdmap-app"
FIREBASE_KEY_PATH="${1:-$REPO_ROOT/firebase-service-account.json}"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info() { echo -e "${GREEN}==>${NC} $*"; }
warn() { echo -e "${YELLOW}WARN:${NC} $*"; }

if [ ! -f "$FIREBASE_KEY_PATH" ]; then
  warn "No Firebase service account key found at $FIREBASE_KEY_PATH"
  warn "Get one: Firebase Console -> Project Settings -> Service Accounts -> Generate new private key"
  warn "Then re-run: ./deploy.sh /path/to/key.json"
  exit 1
fi
FIREBASE_SERVICE_ACCOUNT_JSON="$(cat "$FIREBASE_KEY_PATH")"
: "${CORS_ORIGINS:?Set CORS_ORIGINS to the deployed web app origins before deploying (for example: https://your-project.web.app)}"

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

# ── 2. Deploy to Firebase (Firestore rules/indexes + Hosting only — no Storage) ─
info "Deploying to Firebase..."
cd "$FIREBASE_ROOT"
if [ "${SKIP_WEB:-0}" = "0" ]; then
  firebase deploy --only firestore,hosting
else
  firebase deploy --only firestore
fi
cd "$REPO_ROOT"

# ── 3. Supabase project (Postgres + Storage) — shared with the other two ──────
render services list > /dev/null 2>&1 || { warn "Run 'render login' first, then re-run this script."; exit 1; }
source "$REPO_ROOT/provision-supabase.sh"

# ── 4. Push code, deploy backend to Render ────────────────────────────────────
info "Pushing code to GitHub..."
cd "$REPO_ROOT"
git push origin main

info "Setting up Render service..."
GITHUB_REPO=$(git remote get-url origin | sed 's|https://github.com/||;s|\.git$||')

# render services list returns a bare `null` (not `[]`) when there are zero
# services — guard for that explicitly rather than assuming a list.
SERVICE_ID=$(render services list --output json 2>/dev/null | \
  python3 -c "import sys,json; svcs=json.load(sys.stdin) or []; s=next((x for x in svcs if x.get('name')=='$APP_NAME'), None); print(s['id'] if s else '')" 2>/dev/null || echo "")

if [ -z "$SERVICE_ID" ]; then
  echo "    Creating new Render web service..."
  # --type web_service (not "web"), --root-directory backend (Dockerfile is
  # at backend/Dockerfile, not repo root) — confirmed against the live CLI,
  # not assumed from older docs. There is no separate "set env vars" command
  # (`render env` doesn't exist, and `services update` has no --env-var flag)
  # — --env-var only works at creation time, so all of it goes here.
  SERVICE_JSON=$(render services create \
    --name "$APP_NAME" \
    --type web_service \
    --runtime docker \
    --root-directory backend \
    --repo "https://github.com/$GITHUB_REPO" \
    --branch main \
    --plan free \
    --env-var "DATABASE_URL=$DB_URL" \
    --env-var "ENVIRONMENT=production" \
    --env-var "SECRET_KEY=$SECRET_KEY" \
    --env-var "S3_ENDPOINT=$S3_ENDPOINT" \
    --env-var "S3_ACCESS_KEY=$PROJECT_REF" \
    --env-var "S3_SECRET_KEY=$SERVICE_KEY" \
    --env-var "S3_BUCKET=birdmap-photos" \
    --env-var "MODEL_BUCKET=birdmap-models" \
    --env-var "PUBLIC_S3_URL=$PUBLIC_S3_URL" \
    --env-var "MODEL_REGISTER_SECRET=$MODEL_REGISTER_SECRET" \
    --env-var "FIREBASE_SERVICE_ACCOUNT_JSON=$FIREBASE_SERVICE_ACCOUNT_JSON" \
    --env-var "CORS_ORIGINS=$CORS_ORIGINS" \
    --confirm \
    --output json)
  SERVICE_ID=$(echo "$SERVICE_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
  echo "    Service ID: $SERVICE_ID"
  info "Deploy auto-triggered on creation (auto-deploy defaults on)."
else
  echo "    Service ID: $SERVICE_ID"
  warn "Service already existed — env vars are create-time only via this CLI (no update"
  warn "command supports --env-var); set/change them via the Render dashboard if needed."
  info "Triggering a fresh deploy..."
  render deploys create "$SERVICE_ID" --confirm --output json > /dev/null
fi

# Render web service URLs are the deterministic https://<name>.onrender.com
# pattern unless a custom domain is attached — simpler and more reliable
# than parsing CLI JSON output (whose exact shape has already drifted once
# tonight) to find it.
RENDER_URL="https://${APP_NAME}.onrender.com"
info "Render URL (assuming default domain): $RENDER_URL"
"$REPO_ROOT/update-api-url.sh" "$RENDER_URL"

echo ""
info "Deployment complete!"
echo "  Web map:          $(cd "$FIREBASE_ROOT" && firebase hosting:channel:list 2>/dev/null | grep 'live' | awk '{print $2}' || echo '<firebase hosting URL>')"
echo "  API:               $RENDER_URL"
echo "  Supabase project:  https://supabase.com/dashboard/project/$PROJECT_REF"
echo "  Secrets saved to:  backend/.env.supabase"
echo ""
warn "Render free tier sleeps after 15 min of inactivity — first request after takes ~30-60s."
echo ""
info "One more manual step: add these as GitHub Actions secrets so the live-poll"
info "workflow (.github/workflows/live-poll.yml) can run — Settings -> Secrets"
info "and variables -> Actions on the repo, or run:"
echo ""
echo "  gh secret set FIREBASE_SERVICE_ACCOUNT_JSON < \"$FIREBASE_KEY_PATH\""
echo "  gh secret set RENDER_URL --body \"$RENDER_URL\""
echo "  gh secret set SUPABASE_URL --body \"$SUPABASE_URL\""
echo "  gh secret set SUPABASE_ANON_KEY --body \"$ANON_KEY\""
echo ""
info "Google Vision (optional) isn't set — this CLI has no way to set/inspect env vars"
info "after creation, add GOOGLE_CLOUD_API_KEY via the Render dashboard if you want it."
