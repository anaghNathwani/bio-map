# Contributing

> **This guide describes setting up the original REST/Postgres-backed stack** (`backend/`'s separate, self-contained legacy system per `CLAUDE.md`). To work on the live app, see `CLAUDE.md`'s Commands section instead (iOS: `xcodebuild` from Terminal; `ml_pipeline/`: two-venv setup per `docs/ML_PIPELINE.md`). Any reference to `ml_pipeline/train.py` below is stale — that script doesn't currently exist; see `docs/ML_PIPELINE.md`'s "Our in-house training policy" for the current training design.

## Development Setup

Follow the [Getting Started guide](GETTING_STARTED.md) to get the full stack running locally.

---

## Repository Structure

```
birdmap/
├── backend/        FastAPI backend (Python)
├── ios/            iOS SwiftUI app
├── ml_pipeline/    Model training and export pipeline (Python)
├── docs/           This documentation
└── docker-compose.yml
```

---

## Backend Development

The backend uses FastAPI with async SQLAlchemy. The server hot-reloads on file changes when running via Docker Compose.

### Adding a new endpoint

1. Create or edit a file in `backend/app/api/`
2. Register the router in `backend/app/main.py`
3. If a new DB table is needed, add a model in `backend/app/models/` and update `backend/migrations/init.sql`
4. Test via the auto-generated docs at `http://localhost:8000/docs`

### Code style

- Follow PEP 8
- Use type hints on all function signatures
- Use `async def` for all endpoint handlers and DB operations
- Avoid blocking I/O in async handlers — use `boto3` only in non-async service functions (it is called from async endpoints but is itself synchronous; this is acceptable for v1.0; use `aioboto3` if throughput becomes an issue)

### Running tests

```bash
docker-compose exec api python -m pytest backend/tests/ -v
```

---

## iOS Development

### Code style

- SwiftUI views should be small — if a view body exceeds ~60 lines, extract a subview
- All network calls must be `async throws` — never block the main thread
- `@MainActor` on all `ObservableObject` ViewModels
- Use `batteryEfficientSession` in `APIClient` for all network calls — do not introduce new `URLSession.shared` usages
- CoreML inference must run on a dedicated background `DispatchQueue` (not the main actor) — see `BirdClassifier.inferenceQueue`
- Cache expensive ML objects (`VNCoreMLModel`, `MLModel`) per model version — call `invalidateCache()` after a model update
- GPS-dependent code must use `kCLLocationAccuracyHundredMeters` or coarser unless sub-100m precision is specifically justified
- New shared mutable state that is accessed from async contexts must use `actor` isolation (see `UploadQueue`)

### Adding a new screen

1. Create a new `.swift` file under `ios/BirdMap/BirdMap/Views/`
2. Add it to the appropriate tab in `ContentView.swift` or as a navigation destination
3. Add any new API calls to `APIClient.swift`
4. Add any new model types to `Models/Sighting.swift`

### Testing on device

Physical device testing is required for:
- Camera capture (`AVCaptureSession` does not work in simulator)
- GPS location (simulator fakes GPS — acceptable for basic testing)
- CoreML inference (works in simulator but GPU acceleration is device-only)

---

## ML Pipeline Development

### Adding a new augmentation

Edit the `train_tf` transforms in `ml_pipeline/train.py`. Keep the validation transform (`val_tf`) as resize + crop + normalize only — do not augment validation data.

### Experimenting with a different base model

Replace `models.efficientnet_b0` with any `torchvision.models` entry. Update the classifier head replacement line:

```python
# EfficientNet-B0
model.classifier[1] = nn.Linear(model.classifier[1].in_features, len(class_names))

# ResNet-50
model.fc = nn.Linear(model.fc.in_features, len(class_names))

# MobileNetV3-Small
model.classifier[3] = nn.Linear(model.classifier[3].in_features, len(class_names))
```

---

## Git Workflow

- Branch from `main` for all changes
- Branch naming: `feature/`, `fix/`, `docs/`, `ml/`
- PRs require one approval before merging
- Squash and merge to keep main history clean
- Write a meaningful PR description explaining the *why*, not just the *what*

### Commit message format

```
<type>: <short description>

<optional body>
```

Types: `feat`, `fix`, `docs`, `refactor`, `test`, `ml`, `chore`

Examples:
```
feat: add bbox filtering to sightings endpoint
fix: offline queue not flushing on app foreground
ml: switch base model to EfficientNet-B2 for better accuracy
docs: add data model ER diagram
```

---

## Reporting Issues

Open a GitHub Issue with:

1. **Summary** — one sentence
2. **Steps to reproduce** — numbered list
3. **Expected behaviour** — what should happen
4. **Actual behaviour** — what actually happens
5. **Environment** — iOS version, device, backend version, model version

---

## Roadmap Items Open for Contribution

The following items from the [MoSCoW document](MOSCOW.md) are well-scoped for external contributors:

| Item | Difficulty | Notes |
|---|---|---|
| Species autocomplete (C1) | Medium | Needs a species name list endpoint on the backend |
| GeoJSON export endpoint (C3) | Low | PostGIS `ST_AsGeoJSON` + FastAPI endpoint |
| Dark mode polish (C10) | Low | Audit all hardcoded colours |
| Sighting privacy toggle (C15) | Medium | Store `is_precise` flag; round coordinates to 0.1° on GET |
| Annotation offline queue (v1.0 gap) | Medium | Mirror `UploadQueue` actor pattern for annotations |
| Map sighting cache (C6 equivalent) | Medium | Cache last fetched sightings so map isn't empty on offline launch |
