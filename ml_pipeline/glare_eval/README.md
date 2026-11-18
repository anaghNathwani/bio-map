# Sunrise / sunset glare: evaluation harness

Measures how the on-device photo classifier (Google AIY Birds V1, `BundledBirdModel.tflite`) copes with low-sun photos, and
checks the correction the app applies (`ios/BioMap/BioMap/ML/GlareCorrector.swift`).

| File | What it does |
|---|---|
| `fetch_set.py` | Downloads ~3 openly licensed (CC0 / CC-BY / CC-BY-SA), research-grade iNaturalist photos for each of 59 species the model knows. The photos stay **outside the repo** and are only used to measure the model, never to train it. |
| `glare_lib.py` | The glare simulator (warm cast, veiling sun with flare ghosts, backlit, silhouette), the measurements, and the candidate corrections. The final one is `adaptive()`. |
| `solar.py`, `fetch_lowsun.py`, `real_eval.py`, `horizon_analysis.py` | The REAL-photo version: pick iNaturalist photos by the sun's height at capture time (daylight, golden hour, within 3° of the horizon), measure the model on them, and test candidate corrections. Photos go outside the repo (`../glare_data`). This showed the simulation was unrealistic; see `docs/GLARE_WEIGHT_PROGRAMMING.md`. |
| `eval.py` | Runs every condition × correction through the real `.tflite` model and prints top-1, "shown" and "wrong" rates. `--half even|odd` re-checks on half the species. |
| `dump_parity_cases.py`, `parity_main.swift`, `check_swift_parity.sh` | Confirms the Swift `GlareCorrector` produces the same decisions and pixels as `adaptive()`. |

```bash
cd ml_pipeline && source .venv/bin/activate
python glare_eval/fetch_set.py --out /tmp/glare_set
python glare_eval/eval.py --set /tmp/glare_set --pipelines none,adaptive
glare_eval/check_swift_parity.sh /tmp/glare_set        # needs Xcode's swiftc
```

**Read this first:** the simulator below turned out not to match real low-sun photos (the correction it justified does nothing on real ones), so use the real-photo tools for any conclusion.

Metrics: **top1** = best class is the right species; **shown** = the app would show the right species (best class right and
confidence ≥ 0.5); **wrong** = the app would confidently show a wrong species.

**Limits.** There is no labelled set of real sunrise/sunset photos, so glare is *simulated*. Treat the numbers as "does this help
against the usual low-sun failure modes", not field accuracy. The gate thresholds were read off the clean-vs-glare measurement
distributions rather than tuned on accuracy, and the gains held on both halves of the species list, but a real-photo set would
be the proper test. The simulator is the weak point: add real glare photos here if you collect them (for example from
sightings users submit at dawn and dusk, with their consent).
