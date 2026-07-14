#!/usr/bin/env bash
# BirdMap one-shot deployment: Supabase (DB + storage) + Render (API)
# Run after: supabase login && render workspace set
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="birdmap-api"
SUPABASE_PROJECT_NAME="birdmap"

echo "==> Checking auth..."
supabase projects list > /dev/null 2>&1 || { echo "ERROR: Run 'supabase login' first"; exit 1; }
render services list > /dev/null 2>&1 || { echo "ERROR: Run 'render workspace set' first"; exit 1; }

# ── 1. Supabase project ────────────────────────────────────────────────────────
echo "==> Creating Supabase project (this takes ~60s)..."
ORG_ID=$(supabase orgs list --output json | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['id'])")
DB_PASSWORD=$(python3 -c "import secrets; print(secrets.token_urlsafe(24))")

PROJECT_JSON=$(supabase projects create "$SUPABASE_PROJECT_NAME" \
  --org-id "$ORG_ID" \
  --db-password "$DB_PASSWORD" \
  --region us-east-1 \
  --output json 2>/dev/null || true)

# If project already exists, fetch it
if [ -z "$PROJECT_JSON" ] || echo "$PROJECT_JSON" | grep -q "error"; then
  echo "    (project may already exist, fetching...)"
  PROJECT_JSON=$(supabase projects list --output json | \
    python3 -c "import sys,json; ps=json.load(sys.stdin); p=next(x for x in ps if x['name']=='$SUPABASE_PROJECT_NAME'); print(json.dumps(p))")
fi

PROJECT_REF=$(echo "$PROJECT_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
echo "    Project ref: $PROJECT_REF"

echo "==> Waiting for Supabase project to be ready..."
for i in $(seq 1 60); do
  STATUS=$(supabase projects list --output json | \
    python3 -c "import sys,json; ps=json.load(sys.stdin); p=next((x for x in ps if x['id']=='$PROJECT_REF'), {}); print(p.get('status',''))" 2>/dev/null || echo "")
  [ "$STATUS" = "ACTIVE_HEALTHY" ] && break
  echo "    Status: $STATUS (${i}s)..."
  sleep 5
done

# ── 2. Enable PostGIS & get credentials ───────────────────────────────────────
echo "==> Enabling PostGIS extension..."
supabase db execute --project-ref "$PROJECT_REF" \
  --sql "CREATE EXTENSION IF NOT EXISTS postgis;" 2>/dev/null || \
  echo "    (PostGIS may already be enabled)"

echo "==> Fetching Supabase credentials..."
KEYS_JSON=$(supabase projects api-keys --project-ref "$PROJECT_REF" --output json)
SERVICE_KEY=$(echo "$KEYS_JSON" | python3 -c "import sys,json; ks=json.load(sys.stdin); print(next(x['api_key'] for x in ks if x['name']=='service_role'))")

# Connection string — use transaction pooler (port 6543) for asyncpg compatibility
DB_URL="postgresql+asyncpg://postgres.${PROJECT_REF}:${DB_PASSWORD}@aws-0-us-east-1.pooler.supabase.com:6543/postgres?prepared_statement_cache_size=0"

# Supabase Storage S3-compatible endpoint
S3_ENDPOINT="https://${PROJECT_REF}.supabase.co/storage/v1/s3"
S3_ACCESS_KEY="$PROJECT_REF"
S3_SECRET_KEY="$SERVICE_KEY"
PUBLIC_S3_URL="https://${PROJECT_REF}.supabase.co/storage/v1"

MODEL_REGISTER_SECRET=$(python3 -c "import secrets; print(secrets.token_hex(32))")
SECRET_KEY=$(python3 -c "import secrets; print(secrets.token_hex(32))")

# ── 3. Push code to GitHub ────────────────────────────────────────────────────
echo "==> Pushing code to GitHub..."
cd "$REPO_ROOT"
git push origin main

# ── 4. Create Render service ──────────────────────────────────────────────────
echo "==> Setting up Render service..."
GITHUB_REPO=$(git remote get-url origin | sed 's|https://github.com/||;s|\.git$||')

# Check if service already exists
SERVICE_ID=$(render services list --output json 2>/dev/null | \
  python3 -c "import sys,json; svcs=json.load(sys.stdin); s=next((x for x in svcs if x.get('name')=='$APP_NAME'), None); print(s['id'] if s else '')" 2>/dev/null || echo "")

if [ -z "$SERVICE_ID" ]; then
  echo "    Creating new Render web service..."
  SERVICE_JSON=$(render services create \
    --name "$APP_NAME" \
    --type web \
    --runtime docker \
    --repo "https://github.com/$GITHUB_REPO" \
    --branch main \
    --plan free \
    --output json 2>/dev/null)
  SERVICE_ID=$(echo "$SERVICE_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
fi
echo "    Service ID: $SERVICE_ID"

echo "==> Setting Render environment variables..."
render env set \
  --service "$SERVICE_ID" \
  DATABASE_URL="$DB_URL" \
  SECRET_KEY="$SECRET_KEY" \
  S3_ENDPOINT="$S3_ENDPOINT" \
  S3_ACCESS_KEY="$S3_ACCESS_KEY" \
  S3_SECRET_KEY="$S3_SECRET_KEY" \
  PUBLIC_S3_URL="$PUBLIC_S3_URL" \
  MODEL_REGISTER_SECRET="$MODEL_REGISTER_SECRET" \
  CORS_ORIGINS="*"

echo "==> Triggering Render deploy..."
render deploys create --service "$SERVICE_ID" --output json > /dev/null

# ── 5. Get Render URL & patch iOS project ────────────────────────────────────
echo "==> Waiting for Render service URL..."
for i in $(seq 1 20); do
  RENDER_URL=$(render services show --service "$SERVICE_ID" --output json 2>/dev/null | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('serviceDetails',{}).get('url',''))" 2>/dev/null || echo "")
  [ -n "$RENDER_URL" ] && break
  sleep 3
done

if [ -n "$RENDER_URL" ]; then
  echo "==> Patching iOS project.yml with $RENDER_URL..."
  sed -i '' "s|https://birdmap-api.fly.dev|$RENDER_URL|g" "$REPO_ROOT/ios/BirdMap/project.yml"
  cd "$REPO_ROOT/ios/BirdMap" && xcodegen generate > /dev/null
  echo "    Xcode project regenerated."
fi

# ── 6. Save secrets locally ───────────────────────────────────────────────────
cat > "$REPO_ROOT/backend/.env.prod" <<EOF
DATABASE_URL=$DB_URL
SECRET_KEY=$SECRET_KEY
S3_ENDPOINT=$S3_ENDPOINT
S3_ACCESS_KEY=$S3_ACCESS_KEY
S3_SECRET_KEY=$S3_SECRET_KEY
S3_BUCKET=birdmap-photos
MODEL_BUCKET=birdmap-models
PUBLIC_S3_URL=$PUBLIC_S3_URL
MODEL_REGISTER_SECRET=$MODEL_REGISTER_SECRET
CORS_ORIGINS=*
EOF
chmod 600 "$REPO_ROOT/backend/.env.prod"

echo ""
echo "✓ Deployment complete!"
echo "  API:              $RENDER_URL"
echo "  Supabase project: https://supabase.com/dashboard/project/$PROJECT_REF"
echo "  Secrets saved to: backend/.env.prod"
echo ""
echo "  Note: Render free tier sleeps after 15 min of inactivity."
echo "  First request after sleep takes ~30s. Acceptable for MVP."
