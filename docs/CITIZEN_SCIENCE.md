# Citizen Science & Biosphere Mapping

> **The "Self-Learning Loop" and training-pipeline details below describe the original REST/Postgres-backed design**, not the live app (see `CLAUDE.md`'s Architecture section for the current Firebase-based system). The live app's actual training approach is different and is documented in `docs/ML_PIPELINE.md`'s "Our in-house training policy": fine-tuning the current pretrained models (not training from scratch) once 500 new community annotations accumulate since the last run, checked every 20 minutes via `ml_pipeline/check_training_trigger.py` — not this doc's `--min-annotations` continuous-flywheel design. As of this writing that trigger only logs; no training code consumes it yet.

## The Model

BioMap follows the **VGI (Volunteered Geographic Information)** model pioneered by projects like OpenStreetMap, iNaturalist, and eBird. Users contribute observations; the community validates them; the aggregated dataset becomes a scientific resource.

---

## The Self-Learning Loop

```
Submit sighting  →  Community annotates  →  Dataset grows
       ↑                                           ↓
Better AI ID   ←   Model deployed to app   ←   Pipeline retrains
```

Each cycle of this loop makes the AI more accurate, which encourages more submissions, which produces more training data. This is a deliberate flywheel — the system is designed to improve with zero additional engineering once enough users are active.

---

## Data Quality

Raw crowdsourced data contains noise. BioMap uses several mechanisms to manage this:

### Plurality voting

When multiple users annotate the same sighting, the training pipeline uses the most common species label as ground truth. Two annotators agreeing on "American Robin" outweighs one annotator saying "House Sparrow".

### Confidence weighting (v1.1+)

Annotations include a self-reported confidence score (0–1). Future training iterations will weight annotations by this score, giving more influence to high-confidence labels.

### Expert badges (v1.2+)

Verified ornithologists and experienced birders can be granted an "Expert" badge. Their annotations will count more in the plurality vote — e.g. one expert annotation may count as 3 regular annotations.

### Minimum sample threshold

The training pipeline only includes species with at least `--min-annotations` labelled examples. This prevents the model from being confused by rare, inconsistently labelled species.

---

## Biosphere Mapping

Every sighting is stored as a PostGIS geographic point with a timestamp. This data can be used to:

### Generate species distribution maps

```sql
-- All sightings of American Robin in California
SELECT latitude, longitude, created_at
FROM sightings s
JOIN annotations a ON a.sighting_id = s.id
WHERE a.species = 'American Robin'
  AND ST_Within(
    s.location,
    ST_MakeEnvelope(-124.4, 32.5, -114.1, 42.0, 4326)
  );
```

### Track seasonal migration patterns

By querying sightings by species and month, migration corridors become visible as density shifts northward in spring and southward in autumn.

### Detect population changes

Comparing sighting counts for a species between two time periods reveals expansion, contraction, or displacement. This is the same methodology used by long-running citizen science programs like the Christmas Bird Count.

### Export to mapping tools

The `/sightings` endpoint returns data that can be fed into:

- **QGIS** — industry-standard open-source GIS tool
- **Mapbox** — web mapping with custom styles
- **Google Earth Engine** — large-scale environmental analysis
- **R (sf package)** — statistical spatial analysis

Example GeoJSON conversion (add to backend):

```python
@router.get("/sightings/geojson")
async def sightings_geojson(db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        text("SELECT id, ST_AsGeoJSON(location) as geom, latitude, longitude "
             "FROM sightings")
    )
    features = [
        {
            "type": "Feature",
            "geometry": json.loads(row.geom),
            "properties": {"id": str(row.id), "lat": row.latitude, "lng": row.longitude}
        }
        for row in result
    ]
    return {"type": "FeatureCollection", "features": features}
```

---

## Privacy Considerations

### Location precision

In v1.0, exact GPS coordinates are stored and returned. This is appropriate for open habitats but can be problematic for sensitive nesting sites (e.g. Bald Eagle nests, which may attract disturbance if precisely mapped).

**Planned (C15 in MoSCoW):** A "sensitive location" toggle that rounds public coordinates to the nearest 0.1° (~10 km) while storing the exact location for research purposes.

### User anonymity

Usernames are public on annotations and the leaderboard. Email addresses are never exposed through the API.

---

## Comparison with Related Projects

| Project | Focus | AI | Community annotation | Open data |
|---|---|---|---|---|
| **BioMap** | Birds, geospatial + AI | Self-trained CoreML | Yes | Yes (planned) |
| **iNaturalist** | All taxa | Multiple community AI | Yes | Yes |
| **eBird** | Birds, checklist-based | Limited | Partial | Yes |
| **Merlin (Cornell)** | Bird ID | Pre-trained, static | No | No |
| **Stanford Mosquito** | Mosquitos, sound | Pre-trained | Yes | Research only |

BioMap's distinguishing feature is the **closed-loop retraining** — unlike iNaturalist (which uses community-trained models updated infrequently) or Merlin (static model), BioMap's model updates automatically as community annotations accumulate.

---

## Ethical Use

BioMap data should only be used for:

- Scientific research into bird populations and ecology
- Conservation planning
- Environmental impact assessment
- Education

It must not be used for:

- Locating protected species nests for commercial or trophy purposes
- Selling location data to third parties
- Any use that could harm individual birds or their habitats

Contributors retain moral rights over their photographs. Photo copyright remains with the submitter. By submitting, users grant BioMap a non-exclusive licence to store, display, and use the photo for annotation and model training purposes.
