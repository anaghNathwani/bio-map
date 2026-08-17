#!/usr/bin/env bash
# BirdMap deployment script — Google Cloud Run compute target.
# Same backend code, same Supabase data layer (Postgres + S3-compatible
# Storage) as deploy.sh (Render) — only the compute host differs. Safe to
# keep both configured; run whichever is convenient, or both.
#
# Cloud Run itself requires a GCP project with billing enabled, same as
# Firebase Storage's Blaze requirement — not avoidable via configuration,
# it's how Cloud Run and Cloud Build work. Google Cloud for Education program
# credits (or any other GCP billing arrangement) cover this the same way any
# billing account would; nothing here is Education-program-specific.
#
# Prerequisites (one-time, needs your browser — this script can't do these for you):
#   gcloud CLI:      brew install --cask google-cloud-sdk && gcloud auth login
#   supabase CLI:    brew install supabase/tap/supabase && supabase login
#   A GCP project with billing enabled (console.cloud.google.com -> Billing)
#
# Usage: ./deploy-gcp.sh <gcp-project-id> [path/to/firebase-service-account.json]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
FIREBASE_ROOT="$(dirname "$REPO_ROOT")"
WEB_DIR="$REPO_ROOT/web"
APP_NAME="birdmap-api"
REGION="us-central1"
SUPABASE_PROJECT_NAME="birdmap-app"
GCP_PROJECT_ID="${1:-}"
FIREBASE_KEY_PATH="${2:-$REPO_ROOT/firebase-service-account.json}"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info() { echo -e "${GREEN}==>${NC} $*"; }
warn() { echo -e "${YELLOW}WARN:${NC} $*"; }

if [ -z "$GCP_PROJECT_ID" ]; then
  echo "Usage: ./deploy-gcp.sh <gcp-project-id> [path/to/firebase-service-account.json]"
  echo "List your projects: gcloud projects list"
  exit 1
fi
if [ ! -f "$FIREBASE_KEY_PATH" ]; then
  warn "No Firebase service account key found at $FIREBASE_KEY_PATH"
  warn "Get one: Firebase Console -> Project Settings -> Service Accounts -> Generate new private key"
  exit 1
fi
FIREBASE_SERVICE_ACCOUNT_JSON="$(cat "$FIREBASE_KEY_PATH")"

info "Checking gcloud auth..."
gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | grep -q . || \
  { warn "Run 'gcloud auth login' first, then re-run this script."; exit 1; }
gcloud config set project "$GCP_PROJECT_ID" > /dev/null

info "Checking billing is enabled on $GCP_PROJECT_ID (Cloud Run requires it, even for free-tier usage)..."
BILLING_ENABLED=$(gcloud billing projects describe "$GCP_PROJECT_ID" --format="value(billingEnabled)" 2>/dev/null || echo "false")
if [ "$BILLING_ENABLED" != "True" ]; then
  warn "Billing isn't enabled on $GCP_PROJECT_ID. Enable it (Console -> Billing -> Link a billing"
  warn "account — your Education program billing account, once you have it) then re-run."
  exit 1
fi

# ── 1. Build web app ──────────────────────────────────────────────────────────
if [ ! -f "$WEB_DIR/.env.local" ]; then
  warn "No web/.env.local found. Skipping web build — Firestore rules/indexes will still deploy."
  SKIP_WEB=1
else
  info "Building web app..."
  cd "$WEB_DIR" && npm ci --silent && npm run build && cd "$REPO_ROOT"
  SKIP_WEB=0
fi

# ── 2. Deploy to Firebase (Firestore rules/indexes + Hosting only — no Storage) ─
info "Deploying to Firebase..."
cd "$FIREBASE_ROOT"
if [ "${SKIP_WEB:-0}" = "0" ]; then firebase deploy --only firestore,hosting; else firebase deploy --only firestore; fi
cd "$REPO_ROOT"

# ── 3. Supabase project (Postgres + Storage) — shared with deploy.sh ──────────
source "$REPO_ROOT/provision-supabase.sh"

MODEL_REGISTER_SECRET=$(python3 -c "import secrets; print(secrets.token_hex(32))")
SECRET_KEY=$(python3 -c "import secrets; print(secrets.token_hex(32))")

# ── 4. Enable required APIs ────────────────────────────────────────────────────
info "Enabling Cloud Run + Cloud Build + Artifact Registry APIs (idempotent if already on)..."
gcloud services enable run.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com --quiet

# ── 5. Deploy to Cloud Run, building from backend/Dockerfile via Cloud Build ──
info "Building env vars file (avoids shell-escaping the Firebase JSON key — it has"
info "commas/colons/braces that would break gcloud's comma-separated --set-env-vars)..."
ENV_VARS_FILE="$(mktemp)"
# Passed via the environment, not interpolated into the Python source itself —
# env vars pass through as literal strings regardless of content (quotes,
# braces, newlines), no shell-vs-Python double-escaping to get wrong.
DB_URL="$DB_URL" SECRET_KEY="$SECRET_KEY" S3_ENDPOINT="$S3_ENDPOINT" \
PROJECT_REF="$PROJECT_REF" SERVICE_KEY="$SERVICE_KEY" PUBLIC_S3_URL="$PUBLIC_S3_URL" \
MODEL_REGISTER_SECRET="$MODEL_REGISTER_SECRET" \
FIREBASE_SERVICE_ACCOUNT_JSON="$FIREBASE_SERVICE_ACCOUNT_JSON" \
python3 - "$ENV_VARS_FILE" <<'PYEOF'
import os, sys, yaml
path = sys.argv[1]
env = {
    "DATABASE_URL": os.environ["DB_URL"],
    "SECRET_KEY": os.environ["SECRET_KEY"],
    "S3_ENDPOINT": os.environ["S3_ENDPOINT"],
    "S3_ACCESS_KEY": os.environ["PROJECT_REF"],
    "S3_SECRET_KEY": os.environ["SERVICE_KEY"],
    "S3_BUCKET": "birdmap-photos",
    "MODEL_BUCKET": "birdmap-models",
    "PUBLIC_S3_URL": os.environ["PUBLIC_S3_URL"],
    "MODEL_REGISTER_SECRET": os.environ["MODEL_REGISTER_SECRET"],
    "FIREBASE_SERVICE_ACCOUNT_JSON": os.environ["FIREBASE_SERVICE_ACCOUNT_JSON"],
    "CORS_ORIGINS": "*",
}
with open(path, "w") as f:
    yaml.safe_dump(env, f)
PYEOF

info "Deploying to Cloud Run (this builds backend/Dockerfile via Cloud Build — first run takes a few minutes)..."
gcloud run deploy "$APP_NAME" \
  --source="$REPO_ROOT/backend" \
  --region="$REGION" \
  --allow-unauthenticated \
  --port=8000 \
  --env-vars-file="$ENV_VARS_FILE" \
  --quiet

rm -f "$ENV_VARS_FILE"

GCP_URL=$(gcloud run services describe "$APP_NAME" --region="$REGION" --format="value(status.url)")
info "Cloud Run URL: $GCP_URL"

info "Patching iOS project.yml with $GCP_URL..."
sed -i '' "s|https://birdmap-api.fly.dev|$GCP_URL|g; s|https://birdmap-api.onrender.com|$GCP_URL|g" "$REPO_ROOT/ios/BirdMap/project.yml"
cd "$REPO_ROOT/ios/BirdMap" && xcodegen generate > /dev/null
cp Package.resolved.backup BirdMap.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved 2>/dev/null || true
cd "$REPO_ROOT"
echo "    Xcode project regenerated."

# ── 6. Save secrets locally ────────────────────────────────────────────────────
cat > "$REPO_ROOT/backend/.env.gcp" <<EOF
DATABASE_URL=$DB_URL
SECRET_KEY=$SECRET_KEY
S3_ENDPOINT=$S3_ENDPOINT
S3_ACCESS_KEY=$PROJECT_REF
S3_SECRET_KEY=$SERVICE_KEY
S3_BUCKET=birdmap-photos
MODEL_BUCKET=birdmap-models
PUBLIC_S3_URL=$PUBLIC_S3_URL
MODEL_REGISTER_SECRET=$MODEL_REGISTER_SECRET
CORS_ORIGINS=*
EOF
chmod 600 "$REPO_ROOT/backend/.env.gcp"

echo ""
info "Deployment complete!"
echo "  Web map:          $(cd "$FIREBASE_ROOT" && firebase hosting:channel:list 2>/dev/null | grep 'live' | awk '{print $2}' || echo '<firebase hosting URL>')"
echo "  API (Cloud Run):   $GCP_URL"
echo "  Supabase project:  https://supabase.com/dashboard/project/$PROJECT_REF"
echo "  Secrets saved to:  backend/.env.gcp"
echo ""
info "Cloud Run scales to zero when idle (unlike Render, no fixed sleep/wake schedule —"
info "cold start only on the first request after a quiet period)."
echo ""
info "GitHub Actions secrets for .github/workflows/live-poll.yml (if not already set):"
echo "  gh secret set FIREBASE_SERVICE_ACCOUNT_JSON < \"$FIREBASE_KEY_PATH\""
echo "  gh secret set RENDER_URL --body \"$GCP_URL\"   # reused as the generic backend keepalive URL"
echo "  gh secret set SUPABASE_URL --body \"$SUPABASE_URL\""
echo "  gh secret set SUPABASE_ANON_KEY --body \"$ANON_KEY\""
