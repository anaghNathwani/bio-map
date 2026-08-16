# Deployment

## Overview and why this architecture

Everything in production runs on free tiers **with no credit card attached anywhere**. That constraint, not just cost minimization, drove several concrete decisions worth knowing before touching this:

- **Firebase Storage is not used**, anywhere, for anything. As of February 2026, Google requires a linked billing account (the Blaze plan) to use Cloud Storage for Firebase at all, even for $0-billed usage within the free tier. Firestore and Firebase Auth are unaffected — only Storage is gated — so they're still used directly.
- **Photo/audio/model blobs live in Supabase Storage instead** — genuinely free, no card, for both private and public buckets (unlike Backblaze B2, whose free tier requires a card specifically for public buckets). Reads are direct public URLs; writes are proxied through the FastAPI backend (`backend/app/api/media.py`), which verifies the caller's Firebase ID token before uploading on their behalf, since Supabase Storage has no native way to authorize a Firebase-issued token itself.
- **The backend's database is Supabase Postgres, not a Render-managed database.** Render's free Postgres tier auto-*deletes* the database after a fixed period; Supabase's free tier only *pauses* after 7 days of inactivity (recoverable, not destructive) — meaningfully different for anything called "production."
- **The backend runs on Render's free web service tier** — no card required, but it sleeps after 15 minutes idle (30-60s cold start on the next request). Fine for infrequent operations (an upload, a Vision lookup); not fine for anything that needs to be always listening.
- **`ml_pipeline/live_poll.py` runs on a GitHub Actions schedule, not as a persistent process** — for the same reason a persistent Firestore listener needs an always-on machine, which isn't free unless you provide your own. Polling on a schedule (`.github/workflows/live-poll.yml`) runs entirely on free CI minutes instead, at the cost of "instant" becoming "within one poll interval" (20 minutes by default).
- **Fly.io is not used.** As of 2024-2025 it discontinued its free tier entirely — a card is required almost immediately.

If any of these constraints get relaxed later (a card becomes acceptable, or budget opens up), the natural upgrade path is: enable Firebase Blaze and move Storage back to Firebase (reverts `storage.rules` from vestigial), or move the backend to a paid Render/Fly instance for always-on reliability instead of sleep/cold-start behavior.

---

## Production deployment

Run once, from the repo root:

```bash
./deploy.sh /path/to/firebase-service-account.json
```

Get that key from Firebase Console → Project Settings → Service Accounts → Generate new private key. It's used by the backend (to verify the app's Firebase ID tokens) and by the GitHub Actions live-poll workflow.

**One-time prerequisites** (need your browser — the script can't do these for you):

```bash
npm install -g firebase-tools && firebase login
brew install supabase/tap/supabase && supabase login
brew install render && render login
```

What the script does:
1. Builds and deploys the web map to Firebase Hosting, and deploys `firestore.rules`/`firestore.indexes.json` (Spark plan, free — unaffected by the Storage/Blaze requirement).
2. Creates (or finds) a Supabase project, enables PostGIS, and fetches its Postgres connection string and Storage credentials.
3. Creates (or finds) a Render web service for `backend/`, sets its environment variables (Supabase Postgres URL, Supabase Storage S3-compatible credentials, the Firebase service account key), and triggers a deploy.
4. Patches `ios/BirdMap/project.yml`'s `API_BASE_URL` with the real Render URL and regenerates the Xcode project.
5. Prints the `gh secret set` commands to finish wiring up `.github/workflows/live-poll.yml` (see below) — this last step needs to be run manually once.

### GitHub Actions secrets (for the live-poll workflow)

The script prints these at the end; they can also be set any time via `gh secret set <NAME>` or the repo's Settings → Secrets and variables → Actions:

| Secret | Value |
|---|---|
| `FIREBASE_SERVICE_ACCOUNT_JSON` | Same key passed to `deploy.sh` |
| `RENDER_URL` | The deployed backend URL (keeps it from sleeping via a periodic `/health` ping) |
| `SUPABASE_URL` | `https://<project-ref>.supabase.co` |
| `SUPABASE_ANON_KEY` | Supabase anon key (keeps the project from pausing after 7 days idle) |

The repo is private, so Actions minutes are metered (2000 free min/month) — the workflow's schedule (`*/20 * * * *`) is deliberately conservative to stay well within that. Making the repo public removes the metering entirely (unlimited free minutes) if faster polling is ever needed.

---

## Local development

```bash
cp backend/.env.example backend/.env   # defaults already point at the Docker Compose stack below
docker compose up -d
docker compose exec api alembic upgrade head
```

This runs Postgres + PostGIS + MinIO (an S3-compatible object store) locally — the same code path the production Supabase setup uses, just pointed at local services instead. No Supabase/Firebase credentials needed for backend-only local dev; the media broker's Firebase token verification will fail without a real `FIREBASE_SERVICE_ACCOUNT_JSON`, so exercising that specific endpoint locally needs either a real key or a temporary bypass.

---

## Monitoring

```bash
curl https://<your-render-url>/health
# {"status":"ok"}
```

Render's dashboard shows deploy logs and request logs directly; there's no separate log aggregation set up. A free uptime checker (e.g. UptimeRobot) pinging `/health` periodically both confirms the service is up and serves as an alternative keepalive to the GitHub Actions ping.

---

## Rollback / disabling a component

- **Revert to Firebase Storage:** restore `storage.rules`'s real content (currently marked vestigial but unchanged), re-add the `FirebaseStorage` SPM product to `ios/BirdMap/project.yml`, and point `FirebaseService.uploadImage`/`uploadAudio` back at the Storage SDK instead of the backend's `/media` endpoints. Requires enabling Blaze.
- **Disable the live-poll workflow:** delete or disable `.github/workflows/live-poll.yml` in the repo's Actions settings. Audio sightings will simply never get an AI suggestion, and annotations will stay `moderation: "pending"` — both fail safe (nothing blocks on this).
- **Roll back the backend:** Render keeps previous deploys; redeploy an earlier one from its dashboard.
