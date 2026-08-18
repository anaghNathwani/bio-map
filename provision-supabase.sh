#!/usr/bin/env bash
# Shared Supabase provisioning — sourced by deploy.sh (Render), deploy-gcp.sh
# (Cloud Run), and deploy-selfhost.sh (your own machine as a server), so all
# three compute targets share the same Postgres + S3-compatible Storage data
# layer. Not meant to be run directly.
#
# Requires SUPABASE_PROJECT_NAME and REPO_ROOT to already be set by the
# caller. Requires `supabase login` to have been run already (checked, not
# done here). If the caller has already exported FIREBASE_SERVICE_ACCOUNT_JSON,
# it's included in the written env file too.
#
# Writes backend/.env.supabase immediately once credentials are in hand —
# before returning to the caller — so a compute-target-specific failure
# afterward (e.g. Render's card gate) never loses this work. All three
# deploy scripts need the exact same env vars, so this is the one file all
# of them read from; there's no separate .env.prod/.env.gcp anymore.
#
# Exports on success: PROJECT_REF, DB_PASSWORD, RAW_DB_URL, DB_URL,
# SERVICE_KEY, ANON_KEY, S3_ENDPOINT, PUBLIC_S3_URL, SUPABASE_URL,
# SECRET_KEY, MODEL_REGISTER_SECRET.

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info() { echo -e "${GREEN}==>${NC} $*"; }
warn() { echo -e "${YELLOW}WARN:${NC} $*"; }

: "${SUPABASE_PROJECT_NAME:?SUPABASE_PROJECT_NAME must be set before sourcing provision-supabase.sh}"
: "${REPO_ROOT:?REPO_ROOT must be set before sourcing provision-supabase.sh}"
ENV_FILE="$REPO_ROOT/backend/.env.supabase"

# Reuse a previous run's credentials outright if they're already on disk —
# this is what makes deploy-selfhost.sh usable without ever installing the
# Supabase CLI on that machine: just copy this one file over.
if [ -f "$ENV_FILE" ]; then
  info "Found existing $ENV_FILE — reusing it instead of re-provisioning."
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
  # The file's keys are the literal env var names the backend container
  # expects (DATABASE_URL, S3_ACCESS_KEY, ...) — remap to the names the rest
  # of these deploy scripts use internally (DB_URL, PROJECT_REF, ...).
  DB_URL="$DATABASE_URL"
  PROJECT_REF="$S3_ACCESS_KEY"
  SERVICE_KEY="$S3_SECRET_KEY"
  ANON_KEY="${SUPABASE_ANON_KEY:-}"
  return 0 2>/dev/null || exit 0
fi

info "Checking Supabase auth..."
supabase projects list > /dev/null 2>&1 || { warn "Run 'supabase login' first, then re-run this script."; exit 1; }

info "Finding or creating Supabase project..."
ORG_ID=$(supabase orgs list --output json | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['id'])")
# hex, not urlsafe-base64: urlsafe can start with '-', which some CLI arg
# parsers (confirmed: this one) misread as an unknown flag rather than a value.
DB_PASSWORD=$(python3 -c "import secrets; print(secrets.token_hex(24))")

set +e
PROJECT_JSON=$(supabase projects create "$SUPABASE_PROJECT_NAME" \
  --org-id "$ORG_ID" \
  --db-password "$DB_PASSWORD" \
  --region us-east-1 \
  --output json)
CREATE_EXIT=$?
set -e

if [ $CREATE_EXIT -ne 0 ] || [ -z "$PROJECT_JSON" ]; then
  echo "    (create failed or project may already exist — checking by name...)"
  PROJECT_JSON=$(supabase projects list --output json | \
    python3 -c "import sys,json; ps=json.load(sys.stdin); p=next((x for x in ps if x['name']=='$SUPABASE_PROJECT_NAME'), None); print(json.dumps(p) if p else '', end='')")
  if [ -z "$PROJECT_JSON" ]; then
    echo "ERROR: 'supabase projects create' failed and no existing project named '$SUPABASE_PROJECT_NAME' was found."
    echo "Re-run with --debug to see the real error: supabase projects create ... --debug"
    exit 1
  fi
  warn "Reusing an existing Supabase project found by name — its real DB password"
  warn "is whatever was set when IT was created, not the one just generated below."
  warn "This will likely produce a DATABASE_URL that can't authenticate. If you"
  warn "have no working backend/.env.supabase from that earlier run either, reset"
  warn "the DB password from the Supabase dashboard (Project Settings -> Database)"
  warn "and edit backend/.env.supabase's DATABASE_URL by hand afterward."
fi

PROJECT_REF=$(echo "$PROJECT_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
echo "    Project ref: $PROJECT_REF"

info "Waiting for Supabase project to be ready..."
for i in $(seq 1 60); do
  STATUS=$(supabase projects list --output json | \
    python3 -c "import sys,json; ps=json.load(sys.stdin); p=next((x for x in ps if x['id']=='$PROJECT_REF'), {}); print(p.get('status',''))" 2>/dev/null || echo "")
  [ "$STATUS" = "ACTIVE_HEALTHY" ] && break
  echo "    Status: $STATUS (${i}0s)..."
  sleep 10
done

# Transaction pooler (port 6543) — plain postgres:// for the Supabase CLI,
# SQLAlchemy-flavored postgresql+asyncpg:// (with prepared statement caching
# disabled, required for pgbouncer) for the backend itself.
RAW_DB_URL="postgresql://postgres.${PROJECT_REF}:${DB_PASSWORD}@aws-0-us-east-1.pooler.supabase.com:6543/postgres"
DB_URL="postgresql+asyncpg://postgres.${PROJECT_REF}:${DB_PASSWORD}@aws-0-us-east-1.pooler.supabase.com:6543/postgres?prepared_statement_cache_size=0"

info "Enabling PostGIS extension..."
supabase db query --db-url "$RAW_DB_URL" "CREATE EXTENSION IF NOT EXISTS postgis;" 2>/dev/null || \
  echo "    (PostGIS may already be enabled, or the project isn't ready yet — verify manually if needed)"

info "Fetching Supabase credentials..."
KEYS_JSON=$(supabase projects api-keys --project-ref "$PROJECT_REF" --output json)
SERVICE_KEY=$(echo "$KEYS_JSON" | python3 -c "import sys,json; ks=json.load(sys.stdin); print(next(x['api_key'] for x in ks if x['name']=='service_role'))")
ANON_KEY=$(echo "$KEYS_JSON" | python3 -c "import sys,json; ks=json.load(sys.stdin); print(next(x['api_key'] for x in ks if x['name']=='anon'))")
S3_ENDPOINT="https://${PROJECT_REF}.supabase.co/storage/v1/s3"
PUBLIC_S3_URL="https://${PROJECT_REF}.supabase.co/storage/v1"
SUPABASE_URL="https://${PROJECT_REF}.supabase.co"

SECRET_KEY=$(python3 -c "import secrets; print(secrets.token_hex(32))")
MODEL_REGISTER_SECRET=$(python3 -c "import secrets; print(secrets.token_hex(32))")

info "Writing $ENV_FILE (all three compute targets read from this one file)..."
{
  echo "DATABASE_URL=$DB_URL"
  echo "SECRET_KEY=$SECRET_KEY"
  echo "S3_ENDPOINT=$S3_ENDPOINT"
  echo "S3_ACCESS_KEY=$PROJECT_REF"
  echo "S3_SECRET_KEY=$SERVICE_KEY"
  echo "S3_BUCKET=birdmap-photos"
  echo "MODEL_BUCKET=birdmap-models"
  echo "PUBLIC_S3_URL=$PUBLIC_S3_URL"
  echo "MODEL_REGISTER_SECRET=$MODEL_REGISTER_SECRET"
  echo "CORS_ORIGINS=*"
  if [ -n "${FIREBASE_SERVICE_ACCOUNT_JSON:-}" ]; then
    echo "FIREBASE_SERVICE_ACCOUNT_JSON=$FIREBASE_SERVICE_ACCOUNT_JSON"
  fi
  # Not read by the backend itself — kept here so re-sourcing this file
  # (the reuse path above) restores everything the deploy scripts need,
  # e.g. for the final "gh secret set" printout.
  echo "SUPABASE_URL=$SUPABASE_URL"
  echo "SUPABASE_ANON_KEY=$ANON_KEY"
} > "$ENV_FILE"
chmod 600 "$ENV_FILE"
