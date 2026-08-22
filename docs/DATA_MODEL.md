# Data Model

> **This describes the original Postgres schema** (`backend/`'s separate, self-contained legacy system per `CLAUDE.md` — not called by the live app). The live app's actual schema is Firestore-based: see `CLAUDE.md`'s Architecture section, and `firestore.rules` for the authoritative `users`/`sightings`/`sightings/{id}/annotations`/`model_versions` shapes. Training-time majority-vote label computation described below matches the live app's `topSpecies` field conceptually, but there is no Postgres `model_versions.accuracy` field in the live system — see `docs/ML_PIPELINE.md`'s "Our in-house training policy" for the current (different) training design.

## Entity Relationship Diagram

```
┌─────────────┐         ┌───────────────────┐         ┌──────────────────┐
│    users    │         │     sightings     │         │   annotations    │
├─────────────┤         ├───────────────────┤         ├──────────────────┤
│ id (PK)     │────┐    │ id (PK)           │────┐    │ id (PK)          │
│ email       │    │    │ user_id (FK)      │◄───┘    │ sighting_id (FK) │◄─┐
│ username    │    └───►│ photo_url         │         │ user_id (FK)     │  │
│ hashed_pw   │         │ thumbnail_url     │         │ species          │  │
│ ann_count   │         │ location (POINT)  │         │ confidence       │  │
│ created_at  │         │ latitude          │         │ behavior         │  │
└─────────────┘         │ longitude         │         │ age_plumage      │  │
                        │ notes             │─────────┘ created_at       │  │
                        │ ai_suggestion     │                             │  │
                        │ ai_confidence     │─────────────────────────────┘  │
                        │ created_at        │◄───────────────────────────────┘
                        └───────────────────┘

┌────────────────────┐
│   model_versions   │
├────────────────────┤
│ id (PK, serial)    │
│ version            │
│ s3_key             │
│ num_classes        │
│ accuracy           │
│ is_active          │
│ created_at         │
└────────────────────┘
```

---

## Table Definitions

### `users`

Stores registered user accounts.

| Column | Type | Constraints | Description |
|---|---|---|---|
| `id` | UUID | PK, default gen_random_uuid() | Unique user identifier |
| `email` | VARCHAR(255) | UNIQUE, NOT NULL | Login email |
| `username` | VARCHAR(80) | UNIQUE, NOT NULL | Public display name |
| `hashed_password` | VARCHAR(255) | NOT NULL | bcrypt hash |
| `annotation_count` | INTEGER | DEFAULT 0 | Denormalised count for leaderboard queries |
| `created_at` | TIMESTAMP | DEFAULT NOW() | Registration timestamp |

`annotation_count` is denormalised intentionally. It is incremented in the annotations endpoint rather than computed via a subquery on every leaderboard request.

---

### `sightings`

One row per bird sighting submitted by a user.

| Column | Type | Constraints | Description |
|---|---|---|---|
| `id` | UUID | PK | Unique sighting identifier |
| `user_id` | UUID | FK → users.id, INDEX | Submitting user |
| `photo_url` | VARCHAR(1024) | NOT NULL | Full-resolution photo URL (MinIO) |
| `thumbnail_url` | VARCHAR(1024) | | 400×400 thumbnail URL (MinIO) |
| `location` | GEOMETRY(POINT, 4326) | NOT NULL, GIST INDEX | PostGIS point for spatial queries |
| `latitude` | DOUBLE PRECISION | NOT NULL | Redundant with location; avoids ST_Y() on every read |
| `longitude` | DOUBLE PRECISION | NOT NULL | Redundant with location; avoids ST_X() on every read |
| `notes` | TEXT | | Free text from the submitter |
| `ai_species_suggestion` | VARCHAR(255) | | Top-1 species from the model at upload time |
| `ai_confidence` | DOUBLE PRECISION | | Model confidence 0.0–1.0 |
| `created_at` | TIMESTAMP | DEFAULT NOW() | Sighting timestamp |

`latitude` and `longitude` are stored alongside the PostGIS geometry column to avoid extracting coordinates with `ST_Y()` / `ST_X()` on every API response. This is a deliberate trade-off of slight denormalisation for query simplicity.

#### Spatial index

```sql
CREATE INDEX sightings_location_idx ON sightings USING GIST (location);
```

This index enables efficient bounding-box queries:

```sql
SELECT * FROM sightings
WHERE ST_Within(location, ST_MakeEnvelope(-122.5, 37.7, -122.4, 37.8, 4326));
```

---

### `annotations`

One row per user label on a sighting. A sighting can have many annotations from different users.

| Column | Type | Constraints | Description |
|---|---|---|---|
| `id` | UUID | PK | Unique annotation identifier |
| `sighting_id` | UUID | FK → sightings.id ON DELETE CASCADE, INDEX | The labelled sighting |
| `user_id` | UUID | FK → users.id | The annotating user |
| `species` | VARCHAR(255) | NOT NULL | Species name (free text in v1.0) |
| `confidence` | DOUBLE PRECISION | DEFAULT 1.0 | Annotator self-confidence 0.0–1.0 |
| `behavior` | VARCHAR(255) | | Observed behavior (Foraging, Singing, etc.) |
| `age_plumage` | VARCHAR(100) | | Age or plumage description (Adult, Juvenile, etc.) |
| `created_at` | TIMESTAMP | DEFAULT NOW() | Annotation submission timestamp |

`ON DELETE CASCADE` ensures annotations are removed if a sighting is deleted.

#### Plurality voting (application logic)

The training pipeline determines the ground-truth label by majority vote across all annotations for a sighting:

```python
votes = Counter(ann["species"] for ann in annotations)
species, _ = votes.most_common(1)[0]
```

This is computed at training time, not stored in the database.

---

### `model_versions`

Tracks trained ML model versions and which is currently active.

| Column | Type | Constraints | Description |
|---|---|---|---|
| `id` | SERIAL | PK | Auto-incrementing ID |
| `version` | VARCHAR(50) | UNIQUE | Timestamp-based version string e.g. `20240601_143022` |
| `s3_key` | VARCHAR(1024) | NOT NULL | Object path in MinIO model bucket |
| `num_classes` | INTEGER | NOT NULL | Number of species the model can classify |
| `accuracy` | DOUBLE PRECISION | | Validation accuracy from training run |
| `is_active` | BOOLEAN | DEFAULT TRUE | Only one row should be `TRUE` at a time |
| `created_at` | TIMESTAMP | DEFAULT NOW() | When this version was registered |

When a new model is registered via `POST /model/register`, all existing rows are set to `is_active = FALSE` before the new row is inserted.

---

## Object Storage Layout

### MinIO bucket: `birdmap-photos`

```
birdmap-photos/
├── sightings/
│   ├── {uuid}.jpg          Full-resolution sighting photos
│   └── ...
└── thumbnails/
    ├── {uuid}.jpg          400×400 JPEG thumbnails
    └── ...
```

Photo keys use the same UUID as the path but under different prefixes. This makes it trivial to derive the thumbnail URL from the photo URL.

### MinIO bucket: `birdmap-models`

```
birdmap-models/
└── models/
    ├── birdmap_20240601_143022.mlpackage.zip
    ├── birdmap_20240615_090000.mlpackage.zip
    └── ...
```

Old model versions are retained in storage (not deleted). This allows rollback by updating `is_active` in the database.

---

## Coordinate Reference System

All spatial data uses **EPSG:4326** (WGS84 geographic coordinates) — the same system used by GPS devices, Google Maps, and Apple Maps.

- Longitude: −180 to +180 (east positive)
- Latitude: −90 to +90 (north positive)

PostGIS functions used:

| Function | Usage |
|---|---|
| `ST_MakePoint(lng, lat)` | Create point from coordinates |
| `ST_SetSRID(geom, 4326)` | Assign WGS84 SRS to a geometry |
| `ST_Within(geom, envelope)` | Check if point is inside bounding box |
| `ST_MakeEnvelope(xmin, ymin, xmax, ymax, srid)` | Create bounding box geometry |
