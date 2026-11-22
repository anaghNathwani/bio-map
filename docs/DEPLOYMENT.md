# Deployment

## Overview and why this architecture

Production started from a **no credit card attached anywhere** constraint. That drove several decisions worth knowing before touching this, and a couple of them didn't survive contact with reality — noted below rather than pretending the story is cleaner than it was:

- **Firebase Storage is not used, anywhere, for anything.** As of February 2026, Google requires a linked billing account (the Blaze plan) to use Cloud Storage for Firebase at all, even for $0-billed usage within the free tier; that's still true and still avoided, no billing was ever actually enabled. Instead, sighting photo/audio bytes are compressed client-side and embedded as a base64 data URI directly in the sighting's Firestore document (`FirebaseService.uploadImage`/`uploadAudio`), and the ML pipeline's published models use the same idea, chunked (`publish_model.py` writes ~650KB base64 documents to a Firestore subcollection instead of uploading anywhere). This pattern — compress client-side, skip Storage entirely, embed as base64 in Firestore — follows a prior project (github.com/ishanvi-dekate/team-efficient-epp) that used it successfully at zero cost; see that repo's `Profile.jsx` (avatar upload) and `ChatBot.jsx` (`imageToBase64`). `storage.rules` stays vestigial, unused, kept only in case of a future rollback to real Storage. The FastAPI backend's old media broker (`backend/app/api/media.py`) is unused by the live app — it's part of the legacy, backend-only system described in `CLAUDE.md`, along with the Postgres database that backend uses for its own separate data (not media).
- **The FastAPI backend (`backend/`) is legacy and is not deployed.** The live app does not call it. It runs locally with Docker Compose (see Local development); `render.yaml` and `fly.toml` are kept only as starting points if it is ever hosted. Render and Cloud Run both need a card on file, and Fly.io has no free tier.
- **`ml_pipeline/live_poll.py` runs on a GitHub Actions schedule, not as a persistent process** — for the same reason a persistent Firestore listener needs an always-on machine, which isn't free unless you provide your own. Polling on a schedule (`.github/workflows/live-poll.yml`) runs entirely on free CI minutes instead, at the cost of "instant" becoming "within one poll interval" (20 minutes by default).
- **Fly.io is not used.** As of 2024-2025 it discontinued its free tier entirely — a card is required almost immediately.


**Current status:** the live app depends only on Firebase (Auth, Firestore, Hosting). No backend, Storage bucket or third-party media host is used.

---

## Production deployment

The website deploys with `cd web && npm run build && firebase deploy --only hosting` (config in `web/firebase.json`), or automatically from `.github/workflows/deploy-web.yml` on every push to `main` that touches `web/`, `firebase.json` or `.firebaserc`. That workflow reuses the `FIREBASE_SERVICE_ACCOUNT_JSON` repo secret that `live-poll.yml` needs; its service account must also have the **Firebase Hosting Admin** role. There is no backend to deploy.

### GitHub Actions secrets (for the live-poll workflow)

Set these via `gh secret set <NAME>` or the repo's Settings → Secrets and variables → Actions:

| Secret | Value |
|---|---|
| `FIREBASE_SERVICE_ACCOUNT_JSON` | A Firebase service account key (Project Settings → Service Accounts) |
| `RENDER_URL` | Optional. Only if the legacy backend is hosted on Render (periodic `/health` ping) |

The repo is private, so Actions minutes are metered (2000 free min/month) — the workflow's schedule (`*/20 * * * *`) is deliberately conservative to stay well within that. Making the repo public removes the metering entirely (unlimited free minutes) if faster polling is ever needed — runners stay CPU-only either way, so this affects the minutes budget, not what kind of training work can actually run.

A second job in the same workflow, `check-training-trigger`, runs on the same schedule and checks whether enough newly-processed annotations have accumulated to justify starting a training run (see `docs/ML_PIPELINE.md`'s "Our in-house training policy"). It's cheap (no torch/coremltools, just a Firestore count query) and currently only logs — no training job exists yet to actually consume the signal.

---

### GitHub Actions workflows

| Workflow | Schedule / trigger | Purpose | Needs |
|---|---|---|---|
| `live-poll.yml` | every 20 min | Fallback BirdNET pass for recordings the phone couldn't classify; training-trigger check | `FIREBASE_SERVICE_ACCOUNT_JSON` |
| `notify-waitlist.yml` | every 10 min, or run manually | Emails you new waitlist signups, in-app feedback and **new accounts** (with the total against your TestFlight cap) | `FIREBASE_SERVICE_ACCOUNT_JSON`, `RESEND_API_KEY`, `TESTFLIGHT_CAP` |
| `deploy-web.yml` | push to `main` touching `web/` | Builds and deploys the website to Firebase Hosting | `FIREBASE_SERVICE_ACCOUNT_JSON` (Hosting Admin role) |
| `web-ci.yml` | pushes / PRs | Builds the site and runs the SEO check | none |
| `web-deploy.yml` | manual | Manual Hosting deploy | `FIREBASE_SERVICE_ACCOUNT_JSON` |

**Notification setup (once):**

1. Sign up at [resend.com](https://resend.com) with the email you want alerts at (the sandbox sender `onboarding@resend.dev` only
   delivers to the address you signed up with, unless you verify a domain), and create an API key.
2. In the repo: Settings → Secrets and variables → Actions. On the **Secrets** tab add `RESEND_API_KEY`. On the **Variables**
   tab add `TESTFLIGHT_CAP` (your TestFlight public-link tester limit; a secret of the same name also works). These are
   not "Deploy keys", which is a different page.
3. Actions → "Notify waitlist signups" → **Run workflow** with **Email a test message** ticked. An email titled "BioMap alerts
   are working" should arrive; a 403 from Resend means the recipient isn't the account's email.

The account alert counts Firebase Auth accounts and records a baseline on its first run, so it only emails about accounts
created after that. It stores its progress in the Firestore doc `admin_state/new_users`.

**Actions can be blocked by billing.** If a run fails within seconds with "recent account payments have failed or your
spending limit needs to be increased", GitHub isn't starting the job at all and **every** scheduled workflow is dead until
Settings → Billing and plans is fixed (a public repo gets free Actions). Check the run's annotations first when emails or
polling stop.

---

## Releasing the iOS app

The iOS app is released through TestFlight from Xcode, not CI. See [TESTFLIGHT.md](TESTFLIGHT.md).

---

## Local development

```bash
cp backend/.env.example backend/.env   # defaults already point at the Docker Compose stack below
docker compose up -d
docker compose exec api alembic upgrade head
```

This runs Postgres + PostGIS + MinIO (an S3-compatible object store) locally — the same code path any hosted Postgres and S3-compatible setup would use. No Firebase credentials needed for backend-only local dev; the media broker's Firebase token verification will fail without a real `FIREBASE_SERVICE_ACCOUNT_JSON`, so exercising that specific endpoint locally needs either a real key or a temporary bypass.

---

## Rollback / disabling a component

- **Sighting media is embedded as base64 directly in the Firestore doc** (`FirebaseService.uploadImage`/`uploadAudio`) — no Storage, no Blaze, no backend. To revert to the old backend-broker path instead (e.g. if media needs to outgrow Firestore's 1 MiB document cap): restore `FirebaseService.uploadImage`/`uploadAudio` to call `APIClient`'s `/media` endpoints (removed — see git history), which requires an actually-deployed backend with Postgres and S3-compatible storage, neither of which currently exist.
- **Disable the live-poll workflow:** delete or disable `.github/workflows/live-poll.yml` in the repo's Actions settings. Photo and audio ID both run on-device already, so the only loss is the fallback for a recording the on-device BirdNET model couldn't classify — that sighting simply never gets an AI suggestion. (Its annotation-moderation pass is already dormant — the app hasn't written `moderation: "pending"` since moderation moved on-device — so disabling it changes nothing there.) Fails safe either way (nothing blocks on this).
