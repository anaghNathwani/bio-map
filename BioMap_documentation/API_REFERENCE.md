# API Reference

> **This documents `backend/`'s REST API** — the separate, self-contained legacy Postgres-backed system per `CLAUDE.md`, not called by the live app (which talks to Firestore directly, plus the backend's media-upload broker only). The `/model/register` endpoint below being "called by the ML training pipeline" refers to that legacy pipeline, not the live app's current training design — see `docs/ML_PIPELINE.md`'s "Our in-house training policy".

Base URL: `http://localhost:8000` (development) | `https://api.biomap.app` (production)

All protected endpoints require a `Bearer` token in the `Authorization` header obtained from `/auth/login` or `/auth/register`.

---

## Authentication

### POST `/auth/register`

Create a new user account.

**Request body** (JSON)

| Field | Type | Required | Description |
|---|---|---|---|
| `email` | string | Yes | Valid email address |
| `username` | string | Yes | Unique display name (max 80 chars) |
| `password` | string | Yes | Plaintext password (bcrypt-hashed server-side) |

**Response `201`**

```json
{
  "access_token": "eyJhbGci...",
  "token_type": "bearer"
}
```

**Errors**

| Code | Reason |
|---|---|
| 400 | Email already registered |
| 422 | Validation error (invalid email, missing field) |

---

### POST `/auth/login`

Authenticate and receive a JWT.

**Request body** (JSON)

| Field | Type | Required |
|---|---|---|
| `email` | string | Yes |
| `password` | string | Yes |

**Response `200`**

```json
{
  "access_token": "eyJhbGci...",
  "token_type": "bearer"
}
```

**Errors**

| Code | Reason |
|---|---|
| 401 | Invalid credentials |

---

## Sightings

### POST `/sightings`

Upload a new bird sighting with photo. **Requires auth.**

**Request** — `multipart/form-data`

| Field | Type | Required | Description |
|---|---|---|---|
| `photo` | file | Yes | JPEG or PNG image |
| `latitude` | float | Yes | WGS84 decimal degrees |
| `longitude` | float | Yes | WGS84 decimal degrees |
| `notes` | string | No | Free-text notes |

**Response `201`**

```json
{
  "id": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
  "photo_url": "http://localhost:9000/birdmap-photos/sightings/abc.jpg",
  "thumbnail_url": "http://localhost:9000/birdmap-photos/thumbnails/abc.jpg"
}
```

---

### GET `/sightings`

List sightings, optionally filtered to a bounding box.

**Query parameters**

| Param | Type | Default | Description |
|---|---|---|---|
| `min_lat` | float | — | Southern boundary |
| `max_lat` | float | — | Northern boundary |
| `min_lng` | float | — | Western boundary |
| `max_lng` | float | — | Eastern boundary |
| `limit` | int | 200 | Max results (cap 500) |

If any bbox param is omitted, the bbox filter is skipped and global results are returned.

**Response `200`**

```json
[
  {
    "id": "3fa85f64-...",
    "latitude": 37.7749,
    "longitude": -122.4194,
    "photo_url": "...",
    "thumbnail_url": "...",
    "notes": "Spotted near the feeder",
    "ai_species_suggestion": "American Robin",
    "ai_confidence": 0.87,
    "annotation_count": 3,
    "top_species": "American Robin"
  }
]
```

---

### GET `/sightings/{sighting_id}`

Full detail for a single sighting, including all annotations.

**Path parameters**

| Param | Type | Description |
|---|---|---|
| `sighting_id` | UUID | Sighting identifier |

**Response `200`**

```json
{
  "id": "3fa85f64-...",
  "latitude": 37.7749,
  "longitude": -122.4194,
  "photo_url": "...",
  "thumbnail_url": "...",
  "notes": "...",
  "ai_species_suggestion": "American Robin",
  "ai_confidence": 0.87,
  "annotations": [
    {
      "id": "abc...",
      "species": "American Robin",
      "confidence": 0.95,
      "behavior": "Foraging",
      "age_plumage": "Adult",
      "username": "birdwatcher99"
    }
  ]
}
```

**Errors**

| Code | Reason |
|---|---|
| 404 | Sighting not found |

---

## Annotations

### POST `/sightings/{sighting_id}/annotations`

Submit a species annotation for a sighting. **Requires auth.**

**Request body** (JSON)

| Field | Type | Required | Description |
|---|---|---|---|
| `species` | string | Yes | Common or scientific species name |
| `confidence` | float | No | Annotator self-confidence 0.0–1.0 (default 1.0) |
| `behavior` | string | No | e.g. "Foraging", "Singing", "Perching" |
| `age_plumage` | string | No | e.g. "Adult", "Juvenile", "First winter" |

**Response `201`**

```json
{
  "id": "9b1deb4d-..."
}
```

**Errors**

| Code | Reason |
|---|---|
| 404 | Sighting not found |
| 401 | Not authenticated |

---

## Leaderboard

### GET `/leaderboard`

Ranked list of users by annotation count.

**Query parameters**

| Param | Type | Default | Description |
|---|---|---|---|
| `limit` | int | 50 | Max entries to return |

**Response `200`**

```json
[
  { "username": "ornithologist_dan", "annotation_count": 412 },
  { "username": "birdwatcher99",     "annotation_count": 307 }
]
```

---

## Model

### GET `/model/version`

Returns metadata about the currently active ML model.

**Response `200`**

```json
{
  "version": "20240601_143022",
  "num_classes": 47,
  "accuracy": 0.913,
  "created_at": "2024-06-01T14:30:22"
}
```

**Errors**

| Code | Reason |
|---|---|
| 404 | No model has been trained and registered yet |

---

### GET `/model/download`

Returns a short-lived presigned URL to download the current `.mlpackage` zip.

**Response `200`**

```json
{
  "url": "http://localhost:9000/birdmap-models/models/birdmap_20240601_143022.mlpackage.zip?X-Amz-...",
  "version": "20240601_143022"
}
```

URL expires in **3600 seconds**.

---

### POST `/model/register`

Register a newly trained model version. Called by the ML training pipeline — not the iOS app.

**Request body** (JSON)

| Field | Type | Required | Description |
|---|---|---|---|
| `version` | string | Yes | Unique version string (e.g. `"20240601_143022"`) |
| `s3_key` | string | Yes | Object key in the model bucket |
| `num_classes` | int | Yes | Number of species classes |
| `accuracy` | float | No | Validation accuracy (0–1) |
| `class_names` | array | No | Ordered list of class label strings |

**Response `201`**

```json
{
  "version": "20240601_143022"
}
```

Registering a new version automatically deactivates all previous versions.

---

## Health Check

### GET `/health`

Returns `200` if the API is running. No auth required. Use for load balancer / uptime checks.

```json
{ "status": "ok" }
```

---

## Error Format

All errors follow FastAPI's default format:

```json
{
  "detail": "Human-readable error message"
}
```

Validation errors (422) include per-field detail:

```json
{
  "detail": [
    {
      "loc": ["body", "latitude"],
      "msg": "field required",
      "type": "value_error.missing"
    }
  ]
}
```

---

## Authentication Notes

- Tokens are JWTs signed with `HS256` using the `SECRET_KEY` env variable.
- Token lifetime: **30 days** (configurable via `ACCESS_TOKEN_EXPIRE_MINUTES`).
- No refresh token mechanism in v1.0 — users re-authenticate on expiry.
- All protected endpoints return `401` on missing or invalid token.
