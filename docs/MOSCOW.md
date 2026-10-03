# BioMap — MoSCoW Requirements

MoSCoW prioritization for the BioMap citizen science platform (MVP scope = v1.0).

> **Requirements below referencing the ML training pipeline, `train.py`, or webhook-triggered retraining describe the original REST/Postgres-backed design**, not the live app's current architecture (Firebase-based — see `CLAUDE.md`). The live app's actual training policy has separately shifted from "no in-house training" to fine-tuning pretrained weights on community annotations, triggered every 500 new annotations — see `docs/ML_PIPELINE.md`'s "Our in-house training policy". The trigger mechanism (`ml_pipeline/check_training_trigger.py`) is live; the training/publish code it would call is not yet built.

---

## Must Have

These are non-negotiable for the app to deliver its core value. Without these, BioMap does not function.

| # | Requirement | Rationale |
|---|---|---|
| M1 | User registration and login (email + password) | Every sighting and annotation must be tied to a verified account |
| M2 | Capture a photo of a bird using the device camera | Core data collection action |
| M3 | Automatically attach GPS coordinates to each sighting | Without geolocation, biosphere mapping is impossible |
| M4 | Upload sighting (photo + location + timestamp) to the backend | Data must be persisted centrally to enable community use |
| M5 | View all sightings on an interactive map | Core discovery and citizen science feedback loop |
| M6 | Submit a species annotation on any sighting | Builds the labelled training dataset |
| M7 | Store sightings in a PostGIS-enabled database | Required for spatial queries and biosphere mapping |
| M8 | Backend REST API for all client–server communication | iOS app and ML pipeline both depend on this |
| M9 | Photo storage in object storage (S3/MinIO) | Photos cannot be stored in a relational database at scale |
| M10 | ML training pipeline that consumes annotated sightings | Required to achieve the self-learning loop |
| M11 | Export trained model to CoreML format | iOS on-device inference requires CoreML |
| M12 | App checks for and downloads a new model version silently | Ensures users always run the most up-to-date classifier |
| M13 | On-device bird identification using CoreML + Vision | Core AI value proposition — instant ID without a network call |
| M14 | Offline upload queue — sightings saved locally when no connection | Users are often in the field without connectivity |
| M15 | Info.plist privacy descriptions for camera, location, photos | Apple App Store submission requirement |

---

## Should Have

High-value features that significantly improve the product. Will be included in v1.0 if time permits, otherwise v1.1.

| # | Requirement | Rationale |
|---|---|---|
| S1 | Thumbnail generation on upload (400×400) | Reduces bandwidth on the map view; improves scroll performance |
| S2 | Annotation fields: behavior, age/plumage, confidence score | Richer labels produce better-trained models |
| S3 | Plurality-vote consensus species label per sighting | Reduces noise in the training dataset from disagreeing annotators |
| S4 | Leaderboard of top annotators | Gamification drives annotation volume; essential for cold-start |
| S5 | Map bbox filtering — only fetch sightings in current viewport | Prevents loading thousands of pins on a world-scale map |
| S6 | AI suggestion displayed at upload time | Gives users immediate feedback; increases engagement |
| S7 | Pull-to-refresh on map and leaderboard | Standard UX expectation on iOS |
| S8 | Model version endpoint — app only downloads when version changes | Avoids wasteful re-downloads on every launch |
| S9 | Presigned URLs for model download | Secure, time-limited access without exposing credentials |
| S10 | Docker Compose setup for one-command local deployment | Critical for developer onboarding and reproducibility |
| S11 | Database migration SQL script | Reproducible schema setup for any environment |
| S12 | Annotator can see AI suggestion when annotating | Reduces cognitive load; anchors annotation to model output |

---

## Could Have

Nice-to-have features that add polish or depth. Targeted for v1.2+.

| # | Requirement | Rationale |
|---|---|---|
| C1 | Species autocomplete when typing in the annotation field | Reduces typos and improves label consistency |
| C2 | Filter map by species, date range, or confidence | Power-user feature for researchers and ornithologists |
| C3 | GeoJSON export endpoint for biosphere mapping tools | Allows data to feed into QGIS, Mapbox, external research |
| C4 | Push notifications when a sighting gets annotated | Closes the feedback loop for the original submitter |
| C5 | Sound recording alongside photo (bird call) | Audio is a powerful secondary identification signal |
| C6 | Audio-based classifier (BirdNET integration) | Identify birds by call alone — complementary to vision model |
| C7 | User profile page with sighting history and stats | Increases retention; gives users a sense of contribution |
| C8 | "Expert review" badge for high-confidence annotators | Weighted voting — expert labels count more in training |
| C9 | Sighting detail shows a mini-map of exact location | Contextual map improves user trust in the data |
| C10 | Dark mode support | iOS system setting; expected by modern users |
| C11 | Seasonal heatmap layer on the main map | Reveals migration patterns over time |
| C12 | Automatic retraining trigger via webhook (not manual script) | Removes manual step; keeps model current automatically |
| C13 | Model accuracy and class list visible in app settings | Transparency for advanced users and researchers |
| C14 | iNaturalist / eBird cross-reference for species validation | Validates species names against authoritative taxonomies |
| C15 | Sighting privacy option (obscure exact location) | Protects sensitive nesting sites from disturbance |

---

## Won't Have (this release)

Deliberately out of scope for v1.0. Not a rejection — a deferral with clear reasoning.

| # | Requirement | Rationale for exclusion |
|---|---|---|
| W1 | Social features (following users, comments, likes) | Adds moderation complexity; not the core scientific mission |
| W2 | Android app | iOS-first to validate the concept before porting |
| W3 | Web dashboard / admin panel | Backend API + direct DB access is sufficient for v1.0 ops |
| W4 | Federated / multi-tenant deployment | Single-instance architecture is appropriate at this stage |
| W5 | Integration with eBird real-time API | API costs and rate limits; build own dataset first |
| W6 | AR overlay (point camera at bird, get ID in live view) | High engineering complexity; requires accurate real-time detection |
| W7 | Multi-language / i18n support | English-only for v1.0 to reduce surface area |
| W8 | Paid subscription or in-app purchase | Monetization strategy not yet decided |
| W9 | On-device training (federated learning) | Battery/compute constraints on mobile; centralised training sufficient |
| W10 | Video capture | Storage costs and ML complexity are disproportionate at v1.0 scale |

---

## Summary

| Category | Count |
|---|---|
| Must Have | 15 |
| Should Have | 12 |
| Could Have | 15 |
| Won't Have | 10 |
| **Total** | **52** |

> The v1.0 release targets all **Must Have** items and the majority of **Should Have** items. The self-learning AI loop (M10 → M11 → M12 → M13) is treated as a single end-to-end Must Have chain — partial delivery of this chain is not acceptable for v1.0.
