# Deployment

## Overview and why this architecture

Production started from a **no credit card attached anywhere** constraint. That drove several decisions worth knowing before touching this, and a couple of them didn't survive contact with reality — noted below rather than pretending the story is cleaner than it was:

- **Firebase Storage is not used**, anywhere, for anything. As of February 2026, Google requires a linked billing account (the Blaze plan) to use Cloud Storage for Firebase at all, even for $0-billed usage within the free tier. Firestore and Firebase Auth are unaffected — only Storage is gated — so they're still used directly.
- **Photo/audio/model blobs live in Supabase Storage instead** — genuinely free, no card, for both private and public buckets (confirmed live; unlike Backblaze B2, whose free tier requires a card specifically for public buckets, and unlike Cloudflare R2, whose card requirement is disputed even in its own community). Reads are direct public URLs; writes are proxied through the FastAPI backend (`backend/app/api/media.py`), which verifies the caller's Firebase ID token before uploading on their behalf, since Supabase Storage has no native way to authorize a Firebase-issued token itself.
- **The backend's database is Supabase Postgres, not a Render-managed database.** Render's free Postgres tier auto-*deletes* the database after a fixed period; Supabase's free tier only *pauses* after 7 days of inactivity (recoverable, not destructive) — meaningfully different for anything called "production."
- **Backend compute has two supported targets, both fine to keep configured at once — pick whichever fits:**
  - **Render** (`deploy.sh`) — despite its own docs and widespread reporting saying otherwise, this project's workspace was rejected with `need_payment_info` when actually attempting to create a free-plan service (confirmed live, not assumed). A card is required. Sleeps after 15 min idle (30-60s cold start on next request).
  - **Google Cloud Run** (`deploy-gcp.sh`) — also requires billing enabled on the GCP project (same as Firebase Blaze; not avoidable, that's how Cloud Run/Cloud Build billing works, regardless of program). Scales to zero when idle rather than sleeping on a fixed schedule. A natural fit if billing is covered by a Google Cloud for Education (or similar institutional/credit) arrangement rather than a personal card.
  - Koyeb was also tried and abandoned — it's pivoted toward AI-model-inference hosting rather than general app hosting, no API-key/billing management surface was reachable for a fresh account.
  - Both compute targets share the **same Supabase project** (`provision-supabase.sh`, sourced by both deploy scripts) — the data layer doesn't change based on where the container runs.
- **`ml_pipeline/live_poll.py` runs on a GitHub Actions schedule, not as a persistent process** — for the same reason a persistent Firestore listener needs an always-on machine, which isn't free unless you provide your own. Polling on a schedule (`.github/workflows/live-poll.yml`) runs entirely on free CI minutes instead, at the cost of "instant" becoming "within one poll interval" (20 minutes by default).
- **Fly.io is not used.** As of 2024-2025 it discontinued its free tier entirely — a card is required almost immediately.

The practical lesson embedded in the deploy scripts themselves: every platform's "free, no card" claim in this list was verified by actually attempting the action, not by reading docs or search results — three separate platforms (Render, Koyeb, and disputed reports on Cloudflare R2) turned out to not match their own marketing once actually tested this session.

**Current status, confirmed directly: no Supabase project has actually been provisioned for this app.** `backend/.env` on disk only has local Docker-Compose dev placeholders (`minio:9000`, `minioadmin`); no `backend/.env.supabase` exists anywhere, which is what `provision-supabase.sh` would have written had it been run. This means Storage-backed production features (photo/audio upload via the backend's media broker, and `ml_pipeline/publish_model.py`) have likely never worked in production, regardless of whatever else in this doc describes as "confirmed live." Provisioning one for real needs an interactive `supabase login` (browser OAuth) that has to be done by a human, then `SUPABASE_PROJECT_NAME=... REPO_ROOT="$(pwd)" source ./provision-supabase.sh`.

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

The repo is private, so Actions minutes are metered (2000 free min/month) — the workflow's schedule (`*/20 * * * *`) is deliberately conservative to stay well within that. Making the repo public removes the metering entirely (unlimited free minutes) if faster polling is ever needed — runners stay CPU-only either way, so this affects the minutes budget, not what kind of training work can actually run.

A second job in the same workflow, `check-training-trigger`, runs on the same schedule and checks whether enough newly-processed annotations have accumulated to justify starting a training run (see `docs/ML_PIPELINE.md`'s "Our in-house training policy"). It's cheap (no torch/coremltools, just a Firestore count query) and currently only logs — no training job exists yet to actually consume the signal.

---

## Production deployment (Google Cloud Run alternative)

Same result as `deploy.sh`, different compute host — same Supabase project (Postgres + Storage), same Firestore/Hosting deploy, backend built straight from `backend/Dockerfile` via Cloud Build instead of Render.

```bash
gcloud auth login
gcloud projects list   # find or create the project ID to deploy into
./deploy-gcp.sh <gcp-project-id> /path/to/firebase-service-account.json
```

**One-time prerequisites:**

```bash
brew install --cask google-cloud-sdk && gcloud auth login
brew install supabase/tap/supabase && supabase login   # if not already done for deploy.sh
```

The GCP project needs **billing enabled** (Console → Billing → link a billing account) before this will run — Cloud Run and Cloud Build require it regardless of actual usage, the same shape as Firebase's Blaze requirement. The script checks this up front and exits with a clear message rather than failing partway through if it's missing. This is a natural fit once a Google Cloud for Education (or other institutional) billing account is available, since that's what backs the billing account rather than a personal card.

What it does differently from `deploy.sh`: enables the Cloud Run/Cloud Build/Artifact Registry APIs, writes all backend env vars (including the Firebase service account JSON, which contains commas/braces/colons that would break `gcloud`'s comma-separated `--set-env-vars` format) to a temporary YAML file via `--env-vars-file` instead, and deploys with `gcloud run deploy --source=backend`.

Cloud Run scales to zero when idle rather than sleeping on Render's fixed 15-minute schedule — cold start only happens after a genuinely quiet period, not a fixed timer.

---

## Production deployment (self-hosted alternative — your own machine as a temporary server)

For a pitch/demo period before Cloud Run funding comes through: run the exact same backend container on a spare machine instead of a cloud platform. Same Supabase data layer, same `backend/Dockerfile`. Written for a fresh **Ubuntu Server** install — modest hardware is fine (an old i3 with 16GB RAM and no GPU runs this comfortably; nothing here does on-device ML, the heaviest thing is `tensorflow`'s CPU-only inference path for BirdNET).

**On your Mac**, generate the shared credentials first if you haven't already (this alone doesn't need Render or GCP to succeed):
```bash
SUPABASE_PROJECT_NAME=birdmap-app REPO_ROOT="$(pwd)" source ./provision-supabase.sh
```
This writes `backend/.env.supabase` — copy that one file to the PC (`scp`, a USB drive, whatever's easiest).

**On the PC** (after installing Ubuntu Server and cloning this repo there):
```bash
git clone https://github.com/anaghNathwani/bird-app.git && cd bird-app/birdmap
# copy backend/.env.supabase here first
./deploy-selfhost.sh
```

What it does: installs Docker and `cloudflared` if missing, builds `backend/Dockerfile` and runs it with `--restart unless-stopped` (survives crashes and reboots), then exposes it via a **Cloudflare Tunnel quick tunnel** — free, no Cloudflare account, no domain needed, gives a real `https://*.trycloudflare.com` URL. Installed as a systemd service (`birdmap-tunnel`) so it also survives reboots.

**The one real tradeoff**, confirmed rather than assumed: a Cloudflare Tunnel only gets a *stable, unchanging* URL if it's a *named* tunnel, which requires owning a domain on Cloudflare DNS. Without one, quick tunnels are the only option, and the URL changes every time the tunnel process restarts (reboot, crash, manual restart). The systemd service logs every URL it's assigned to `/var/log/birdmap-tunnel-url.log` — after any restart, check that file and re-point the app:
```bash
# on your Mac
./update-api-url.sh https://whatever-the-new-one-is.trycloudflare.com
```
If this ends up running for longer than "temporary," a cheap domain added to Cloudflare removes this whole caveat (persistent named tunnel, no more URL rotation) — not built here since it wasn't asked for and isn't free.

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
- **Roll back the backend:** Render keeps previous deploys; redeploy an earlier one from its dashboard. Cloud Run keeps previous revisions too — `gcloud run services update-traffic birdmap-api --region=us-central1 --to-revisions=<revision>=100`. Self-hosted: `docker logs birdmap-api` / rebuild from an earlier commit.
- **Switch compute target:** all three deploy scripts call the same `update-api-url.sh` to patch `ios/BirdMap/project.yml`'s `API_BASE_URL` — running any one of them just repoints the app at whichever ran last. All three backends stay live independently unless explicitly torn down.
- **Stop self-hosting:** `docker rm -f birdmap-api && sudo systemctl disable --now birdmap-tunnel`.
