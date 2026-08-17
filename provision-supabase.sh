#!/usr/bin/env bash
# Shared Supabase provisioning — sourced by deploy.sh (Render) and
# deploy-gcp.sh (Cloud Run), so both compute targets share the same
# Postgres + S3-compatible Storage data layer. Not meant to be run directly.
#
# Requires SUPABASE_PROJECT_NAME to already be set by the caller. Requires
# `supabase login` to have been run already (checked, not done here).
#
# Exports on success: PROJECT_REF, DB_PASSWORD, RAW_DB_URL, DB_URL,
# SERVICE_KEY, ANON_KEY, S3_ENDPOINT, PUBLIC_S3_URL, SUPABASE_URL.

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info() { echo -e "${GREEN}==>${NC} $*"; }
warn() { echo -e "${YELLOW}WARN:${NC} $*"; }

: "${SUPABASE_PROJECT_NAME:?SUPABASE_PROJECT_NAME must be set before sourcing provision-supabase.sh}"

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
  # Reusing an existing project means DB_PASSWORD (freshly generated above)
  # is very likely NOT its real password (unrecoverable after creation) —
  # only trust it when we just created the project ourselves this run.
  REUSED_EXISTING_PROJECT=1
else
  REUSED_EXISTING_PROJECT=0
fi

PROJECT_REF=$(echo "$PROJECT_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
echo "    Project ref: $PROJECT_REF"

if [ "$REUSED_EXISTING_PROJECT" = "1" ]; then
  warn "Reusing an existing project — its real DB password is whatever was set"
  warn "when IT was created, not the one just generated. If backend/.env.prod or"
  warn "backend/.env.gcp from that earlier run still exists, reuse DATABASE_URL"
  warn "from there instead of what this run derives below."
fi

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
