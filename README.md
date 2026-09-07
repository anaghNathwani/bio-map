# BirdMap

BirdMap is a citizen-science iOS app and web map for bird sightings, community
annotations, and bird identification.

## Production architecture

- **iOS app:** SwiftUI, Firebase Auth/Firestore, on-device Core ML photo
  classification, and server-side BirdNET audio analysis.
- **Web map:** React/Vite, Firebase client SDK, and Leaflet.
- **Media broker:** FastAPI verifies Firebase ID tokens and stores photo/audio
  blobs in Supabase Storage. It also contains a separate legacy
  Postgres-backed API.
- **ML operations:** `ml_pipeline/live_poll.py` runs from GitHub Actions every
  20 minutes for audio identification and annotation moderation.

Firebase Storage is intentionally not used. See `CLAUDE.md` and
`docs/DEPLOYMENT.md` for the full architecture and hosting tradeoffs.

## Local development

### Web

```bash
cd web
cp .env.example .env.local
# Fill in the Firebase web app values in .env.local.
npm ci
npm run dev
```

### Backend

```bash
cp backend/.env.example backend/.env
docker compose up -d
docker compose exec api alembic upgrade head
```

The local stack uses PostGIS and MinIO. The media broker additionally needs a
Firebase service-account JSON value in `FIREBASE_SERVICE_ACCOUNT_JSON`.

### iOS

```bash
xcodebuild -project ios/BirdMap/BirdMap.xcodeproj \
  -scheme BirdMap \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -configuration Debug build
```

For a physical device, set the API base URL to the reachable backend address
with the `API_BASE_URL_OVERRIDE` launch argument or update the generated
project configuration.

## Production deployment

Provision Supabase first, then choose a compute target:

```bash
# Render
CORS_ORIGINS="https://your-project.web.app,https://your-project.firebaseapp.com" \
  ./deploy.sh /path/to/firebase-service-account.json

# Google Cloud Run
CORS_ORIGINS="https://your-project.web.app,https://your-project.firebaseapp.com" \
  ./deploy-gcp.sh <gcp-project-id> /path/to/firebase-service-account.json
```

Both targets require their respective account setup and use the same Supabase
Postgres and Storage data layer. Production deployments reject wildcard CORS
and insecure secret defaults. Configure the
`FIREBASE_SERVICE_ACCOUNT_JSON` GitHub secret before enabling the scheduled
live-poll workflow.

See `docs/DEPLOYMENT.md` for provisioning, GitHub Actions secrets,
self-hosting, monitoring, and rollback procedures.

## Validation

```bash
cd web && npm ci && npm run build
python3 -m compileall backend/app ml_pipeline
xcodebuild -project ios/BirdMap/BirdMap.xcodeproj \
  -scheme BirdMap \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -configuration Debug build
```
