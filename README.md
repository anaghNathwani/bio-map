# BioMap

BioMap is a citizen-science iOS app and web map for bird sightings, community
annotations, and on-device bird identification. The iOS app is in public beta on
TestFlight; the web map and marketing site are live at https://getbiomap.web.app.

## Production architecture (the live app)

- **iOS app:** SwiftUI, Firebase Auth + Firestore. On-device ML for
  everything: photo species classification (TensorFlowLiteSwift), a
  multi-bird photo detector (CoreML/Vision), audio call identification
  (BirdNET via TFLite), and annotation moderation (a bundled bird-name
  heuristic). Photo/audio bytes are compressed client-side and embedded as a
  base64 data URI directly in the sighting's Firestore document — **no
  Firebase Storage, no Supabase, no deployed backend of any kind is needed
  for the live app to work.**
- **Widgets:** a widget extension adds home screen and Lock Screen widgets and two
  Lock Screen corner controls (iOS 18+); see `docs/IOS_APP.md`.
- **Web map:** React/Vite, reads sightings directly from Firestore with the
  Firebase client SDK (`web/src/firebase.js`) — no backend involved. Also
  hosts the marketing site (`web/src/pages/LandingPage.jsx` and friends).
- **ML operations (fallback only):** `ml_pipeline/live_poll.py` runs from
  GitHub Actions every 20 minutes as a fallback for audio recordings the
  on-device BirdNET model couldn't classify. Its annotation-moderation pass
  is dormant — the app no longer writes `moderation: "pending"`, since
  moderation moved on-device — but the code hasn't been deleted yet.

Firebase Storage is intentionally not used, and neither is Supabase for the
live app's media. See `CLAUDE.md` and `docs/DEPLOYMENT.md` for the full
architecture and hosting tradeoffs, and `docs/ML_PIPELINE.md` for what each
model runs on and why.

## Releasing the iOS app (TestFlight)

Builds reach testers through TestFlight, uploaded from Xcode on a Mac (needs a paid Apple
Developer Program membership). The short version:

1. Bump `CURRENT_PROJECT_VERSION` (and `MARKETING_VERSION` for a feature release) in the
   top-level `settings` of `ios/BioMap/project.yml`. Every upload needs a higher build number.
2. `cd ios/BioMap && xcodegen generate`, then open **`BioMap.xcworkspace`**.
3. Destination **Any iOS Device (arm64)** → **Product → Archive**.
4. Organizer → **Distribute App → App Store Connect → Upload**. Or **Custom → Export** to get
   `BioMap.ipa` and deliver it with the **Transporter** app.
5. In App Store Connect → TestFlight, wait for processing, then add the build to your
   internal / external groups (external needs Beta App Review). Share the public link.

Full steps, one-time setup, trying a build on your own iPhone without TestFlight, and
troubleshooting are in [`docs/TESTFLIGHT.md`](docs/TESTFLIGHT.md).

## Waitlist, feedback and alerts

- The website's waitlist (hero section) collects **iCloud** emails only (TestFlight invites go to
  the Apple ID) into the Firestore `waitlist` collection.
- In the app, Profile → "Report a bug or suggest a feature" writes to the `feedback` collection.
- `.github/workflows/notify-waitlist.yml` runs `ml_pipeline/notify_waitlist_signups.py` every 10
  minutes and emails you new waitlist signups, new feedback, and **new BioMap accounts** with the
  total against your TestFlight tester cap. It needs the `RESEND_API_KEY` secret and a
  `TESTFLIGHT_CAP` variable; see `docs/DEPLOYMENT.md`. GitHub Actions must be allowed to run
  (billing in good standing), or none of the scheduled jobs start.
- Signups and feedback are readable in the Firebase console under Firestore (`waitlist`, `feedback`).

## Website

The marketing site and live map (`web/`) is prerendered at build time for search engines and deploys to Firebase
Hosting: https://getbiomap.web.app. See `docs/SEO.md` for how discoverability is set up and
`docs/SEO_PLAN.md` for the full checklist.

```bash
cd web && npm run build && npm run seo:check && firebase deploy --only hosting
```

## The legacy FastAPI backend (`backend/`) — optional, not required

An earlier, fully separate Postgres-backed system (its own auth, sightings,
annotations, leaderboard) that the live app **does not call**, kept around
and deployable on request rather than because anything depends on it. The
one thing in the live app that still touches it is an optional Google Vision
bird-ID proxy (`APIClient.identifyImage`), and call sites already degrade
silently without it deployed.

### Running it locally

```bash
cp backend/.env.example backend/.env
docker compose up -d
docker compose exec api alembic upgrade head
```

The local stack uses PostGIS and MinIO. The media broker additionally needs a
Firebase service-account JSON value in `FIREBASE_SERVICE_ACCOUNT_JSON`.

### Deploying it

```bash
# Render — needs a card, confirmed live
./deploy.sh /path/to/firebase-service-account.json

# Google Cloud Run — needs GCP billing enabled
./deploy-gcp.sh <gcp-project-id> /path/to/firebase-service-account.json

# Runs on a spare machine you already have — needs backend/.env.supabase copied over
./deploy-selfhost.sh
```

All three share the same Supabase Postgres data layer, provisioned first via
`provision-supabase.sh`. See `docs/DEPLOYMENT.md` for provisioning, GitHub
Actions secrets, monitoring, and rollback procedures.

## Local development

### Web

```bash
cd web
cp .env.example .env.local
# Fill in the Firebase web app values in .env.local.
npm ci
npm run dev
```

### iOS

Uses CocoaPods (`TensorFlowLiteSwift`) alongside Swift Package Manager —
**build the `.xcworkspace`, not the `.xcodeproj` directly**, or the Pods
integration won't be there:

```bash
cd ios/BioMap
xcodegen generate   # project.yml is the source of truth; this also runs `pod install`
xcodebuild -workspace BioMap.xcworkspace \
  -scheme BioMap \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Debug build
```

To run on your own iPhone, plug it in (Developer Mode on), pick it as the destination in Xcode
and press ⌘R. See `docs/IOS_APP.md` for the app's structure and `CLAUDE.md` for gotchas.

## Validation

```bash
cd web && npm ci && npm run build
python3 -m compileall backend/app ml_pipeline
cd ios/BioMap && xcodebuild -workspace BioMap.xcworkspace \
  -scheme BioMap \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Debug build
```
