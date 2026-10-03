# Getting Started

This guide gets you from zero to a running BirdRadar stack in under 15 minutes.

> **This guide covers the original REST/Postgres-backed stack** (`backend/`'s separate, self-contained legacy system — see `CLAUDE.md`'s Architecture section for the live Firebase-based app and its actual setup commands). Any "Train the ML model" / `train.py` step below is stale — no such script currently exists; see `docs/ML_PIPELINE.md`'s "Our in-house training policy" for how training actually works today.

## Prerequisites

| Tool | Version | Purpose |
|---|---|---|
| Docker Desktop | 4.x+ | Runs PostgreSQL, MinIO, and the API |
| Docker Compose | v2+ | Orchestrates all services |
| Xcode | 15+ | Builds and runs the iOS app |
| Python | 3.11+ | ML training pipeline (optional for first run) |
| `psql` | Any | Runs the DB migration (can use Docker instead) |

---

## Step 1 — Clone and configure

```bash
git clone https://github.com/your-org/birdmap.git
cd birdmap
cp backend/.env.example backend/.env
```

Open `backend/.env` and set a strong `SECRET_KEY`:

```
SECRET_KEY=your-random-64-char-string-here
```

Everything else can stay as the defaults for local development.

---

## Step 2 — Start backend services

```bash
docker-compose up -d
```

This starts:

| Service | Port | UI |
|---|---|---|
| FastAPI | 8000 | http://localhost:8000/docs |
| PostgreSQL + PostGIS | 5432 | — |
| MinIO | 9000 (API) / 9001 (console) | http://localhost:9001 |

Check everything is healthy:

```bash
docker-compose ps
curl http://localhost:8000/health
# {"status":"ok"}
```

---

## Step 3 — Run database migrations

```bash
# Option A: via Docker
docker-compose exec db psql -U birdmap -d birdmap -f /dev/stdin < backend/migrations/init.sql

# Option B: directly if psql is installed locally
psql postgresql://birdmap:birdmap_secret@localhost:5432/birdmap -f backend/migrations/init.sql
```

---

## Step 4 — Open the iOS app in Xcode

```bash
open ios/BirdRadar/BirdRadar.xcodeproj
```

If the project file does not exist yet (this repo ships source files only), create a new Xcode project:

1. **File → New → Project → iOS → App**
2. Product name: `BirdRadar`, Interface: `SwiftUI`, Language: `Swift`
3. Drag all `.swift` files from `ios/BirdRadar/BirdRadar/` into the project navigator
4. Copy `Info.plist` and `BirdRadar.entitlements` into the project root
5. In project settings → Signing & Capabilities, add **Location When In Use**, **Camera**, and **Photo Library** capabilities

### Point the app at your backend

Open `ios/BirdRadar/BirdRadar/Networking/APIClient.swift` and set:

```swift
var baseURL = "http://YOUR_LAN_IP:8000"
```

Replace `YOUR_LAN_IP` with your machine's local IP (e.g. `192.168.1.42`). The iOS simulator can use `http://localhost:8000` directly.

---

## Step 5 — Build and run

Select a simulator or physical device in Xcode and press **⌘R**.

On first launch:
1. Create an account on the login screen
2. Allow location access when prompted
3. Tap **Report** → choose from library or tap **Camera**
4. Take a photo, submit — it appears on the **Map** tab immediately

---

## Step 6 — Train the ML model (optional)

The app works without a model (it simply won't show AI suggestions until one is trained). Once you have at least a handful of annotated sightings:

```bash
cd ml_pipeline
pip install -r requirements.txt

# Get a token by logging in
TOKEN=$(curl -s -X POST http://localhost:8000/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"you@example.com","password":"yourpassword"}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

python train.py \
  --api-url http://localhost:8000 \
  --token "$TOKEN" \
  --min-annotations 5 \
  --epochs 5
```

After training completes, kill and relaunch the iOS app — it will download the new model and show AI species suggestions.

---

## Verifying the full loop

1. Submit 2–3 sightings with photos
2. Annotate them via the **Map** → tap a pin → **Annotate**
3. Run `python train.py --min-annotations 1`
4. Re-open the app → take a new photo → AI suggestion should appear

---

## Useful commands

```bash
# View API logs
docker-compose logs -f api

# Connect to the database
docker-compose exec db psql -U birdmap -d birdmap

# Count sightings
SELECT COUNT(*) FROM sightings;

# Count annotations per species
SELECT species, COUNT(*) FROM annotations GROUP BY species ORDER BY COUNT(*) DESC;

# Reset everything
docker-compose down -v
```

---

## MinIO console

Visit http://localhost:9001 and log in with `minioadmin` / `minioadmin123`.

You can browse uploaded photos under the `birdmap-photos` bucket and trained models under `birdmap-models`.
