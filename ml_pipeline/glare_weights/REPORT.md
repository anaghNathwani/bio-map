# Can we reduce sunrise/sunset glare errors by editing a few weights? Stage 3 result

**Short answer: no reliable effect.** The pre-registered weight edit is safe on ordinary photos, but it does not help with glare by an amount we can tell apart from noise, and combined with the app's existing correction it is, if anything, slightly worse (also within noise). Verdict against the safety budget: **NULL**. Nothing was shipped, and the app and the bundled model were not touched.

## What the edit is

The photo model's first layer has 32 small filters that look at raw colour. One of them (filter 14) is mostly a "red versus blue" detector, and the glare simulation (orange cast) pushes it much harder than normal. The edit softens that one filter: we keep its brightness-pattern part, and halve the part that responds to red-versus-blue difference. In numbers, 27 of the 864 weights in the first-layer weight tensor changed (3.1% of that tensor), by at most 0.28, and each was rounded back to the model's 8-bit number grid. No training or optimiser was used; the recipe is a few lines of arithmetic (`recipe_chroma14_a05.json`). This was the one candidate our planning stage pre-registered from 15 it tried on the development half of the photos.

## How it was tested

- **Photos.** 177 labelled photos of 59 species. Species sorted alphabetically: even positions were the development half (used by earlier stages), odd positions the sealed **test half: 29 species, 87 photos**.
- **Glare.** Simulated (no real labelled glare set exists): four conditions (golden, veil, backlit, silhouette) plus the clean photo, seeded exactly as in `ml_pipeline/glare_eval`.
- **Four systems.** (1) the unedited model; (2) unedited plus the app's glare correction (when the app's measurements say a photo looks glared, it classifies a corrected copy too and blends 30% original / 70% corrected); (3) the candidate alone; (4) candidate plus the app's correction.
- **Metrics.** *Best class right* (top-1); *right answer shown* (best class is right and confidence is at least 0.5, which is what the app would display); *confident wrong* (wrong species shown, excluding the "Not a Bird" class); *margin* (true class's log-probability minus the best rival's; higher is better).
- **Intervals.** 95% paired bootstrap over the 87 photos (2000 resamples, same photos for both systems). One photo is worth about 1.1 points per condition, so intervals are wide.
- **Order of work.** First I reproduced the earlier stage's development-split numbers exactly (see below), then ran the test split **once**.

Sanity check on the development split (90 photos): the unedited model showed the right answer on 58.9% of clean photos and 31.9% / 38.6% on glare (raw / with correction); the candidate gave +1.4 [0.0, +2.8] on glare alone and +0.8 [-0.6, +2.2] with correction. These match the Stage 2 numbers to the decimal. (Scripts must be run with the project's `ml_pipeline/.venv`, TensorFlow 2.15.1; with the newer system TensorFlow, the unedited model's clean score is 2 photos different, because of a different numeric backend, not a data difference. I found this by checking Stage 2's saved inputs.)

## Results on the test half (87 photos, simulated glare, percent)

Rows in italics are differences with 95% intervals in square brackets, in percentage points (margin in logits).

### Right answer shown (best class right and confidence at least 0.5)
| System | clean | golden | veil | backlit | silhouette | glare mean |
|---|---|---|---|---|---|---|
| 1. Unedited model | 57.5 | 47.1 | 35.6 | 36.8 | 8.0 | 31.9 |
| 2. Unedited + app correction | 57.5 | 52.9 | 44.8 | 37.9 | 20.7 | 39.1 |
| 3. Candidate alone | 58.6 | 49.4 | 37.9 | 36.8 | 8.0 | 33.0 |
| 4. Candidate + app correction | 58.6 | 52.9 | 43.7 | 39.1 | 18.4 | 38.5 |
| *Candidate minus unedited (3 - 1)* | +1.1 [+0.0, +3.4] | +2.3 [+0.0, +5.7] | +2.3 [-2.3, +6.9] | +0.0 [+0.0, +0.0] | +0.0 [-3.4, +3.4] | +1.1 [-0.3, +2.6] |
| *Candidate+corr minus corr alone (4 - 2)* | +1.1 [+0.0, +3.4] | +0.0 [-3.4, +3.4] | -1.1 [-3.4, +0.0] | +1.1 [+0.0, +3.4] | -2.3 [-5.7, +0.0] | -0.6 [-2.0, +0.6] |

### Best class right (top-1)
| System | clean | golden | veil | backlit | silhouette | glare mean |
|---|---|---|---|---|---|---|
| 1. Unedited model | 66.7 | 56.3 | 46.0 | 47.1 | 17.2 | 41.7 |
| 2. Unedited + app correction | 66.7 | 63.2 | 57.5 | 52.9 | 33.3 | 51.7 |
| 3. Candidate alone | 65.5 | 55.2 | 49.4 | 48.3 | 18.4 | 42.8 |
| 4. Candidate + app correction | 65.5 | 62.1 | 56.3 | 50.6 | 33.3 | 50.6 |
| *Candidate minus unedited (3 - 1)* | -1.1 [-3.4, +0.0] | -1.1 [-3.4, +0.0] | +3.4 [+0.0, +8.0] | +1.1 [+0.0, +3.4] | +1.1 [+0.0, +3.4] | +1.1 [+0.0, +2.6] |
| *Candidate+corr minus corr alone (4 - 2)* | -1.1 [-3.4, +0.0] | -1.1 [-5.7, +2.3] | -1.1 [-3.4, +0.0] | -2.3 [-6.9, +2.3] | +0.0 [-3.4, +3.4] | -1.1 [-3.2, +0.6] |

### Confidently wrong
| System | clean | golden | veil | backlit | silhouette | glare mean |
|---|---|---|---|---|---|---|
| 1. Unedited model | 11.5 | 10.3 | 10.3 | 11.5 | 8.0 | 10.1 |
| 2. Unedited + app correction | 12.6 | 6.9 | 9.2 | 9.2 | 5.7 | 7.8 |
| 3. Candidate alone | 11.5 | 10.3 | 12.6 | 12.6 | 5.7 | 10.3 |
| 4. Candidate + app correction | 12.6 | 6.9 | 12.6 | 8.0 | 6.9 | 8.6 |
| *Candidate minus unedited (3 - 1)* | +0.0 [+0.0, +0.0] | +0.0 [+0.0, +0.0] | +2.3 [-2.3, +6.9] | +1.1 [+0.0, +3.4] | -2.3 [-5.7, +0.0] | +0.3 [-1.1, +1.7] |
| *Candidate+corr minus corr alone (4 - 2)* | +0.0 [+0.0, +0.0] | +0.0 [+0.0, +0.0] | +3.4 [+0.0, +8.0] | -1.1 [-3.4, +0.0] | +1.1 [+0.0, +3.4] | +0.9 [-0.3, +2.3] |

### Mean true-class margin (logits)
| System | clean | golden | veil | backlit | silhouette | glare mean |
|---|---|---|---|---|---|---|
| 1. Unedited model | 1.31 | 0.24 | -0.63 | -0.84 | -4.31 | -1.39 |
| 2. Unedited + app correction | 1.22 | 0.86 | 0.22 | -0.45 | -2.86 | -0.56 |
| 3. Candidate alone | 1.32 | 0.24 | -0.59 | -0.78 | -4.33 | -1.36 |
| 4. Candidate + app correction | 1.24 | 0.79 | 0.19 | -0.42 | -2.91 | -0.59 |
| *Candidate minus unedited (3 - 1)* | +0.0 [-0.0, +0.1] | +0.0 [-0.1, +0.1] | +0.0 [-0.1, +0.2] | +0.1 [-0.1, +0.2] | -0.0 [-0.1, +0.1] | +0.0 [-0.0, +0.1] |
| *Candidate+corr minus corr alone (4 - 2)* | +0.0 [-0.0, +0.1] | -0.1 [-0.1, -0.0] | -0.0 [-0.1, +0.0] | +0.0 [-0.0, +0.1] | -0.1 [-0.1, +0.0] | -0.0 [-0.1, +0.0] |

## Verdict against the safety budget

| Result | Criterion | Measured on the test split |
|---|---|---|
| PASS | clean top1 fall <= 2 pts and CI lower bound > -5 | -1.1 [-3.4, +0.0] |
| PASS | clean shown-right fall <= 2 pts and CI lower bound > -5 | +1.1 [+0.0, +3.4] |
| PASS | clean wrong-shown does not rise | +0.0 [+0.0, +0.0] |
| **FAIL** | glare shown-right improves in >= 3 of 4 conditions and glare-mean CI lower bound > 0 | 2/4 improved; glare mean +1.1 [-0.3, +2.6] |
| **FAIL** | candidate+correction not worse than correction alone (glare-mean shown CI lower bound >= -1 pt; wrong-shown not higher in glare mean or clean) | shown glare -0.6 [-2.0, +0.6]; wrong glare +0.9 [-0.3, +2.3]; wrong clean +0.0 |
| PASS | outputs finite and softmax sums to 1 (max error < 1e-3) | unedited: finite=True, max|sum-1|=1.3e-06; candidate: finite=True, max|sum-1|=1.4e-06 |

**Overall: NULL.** Safety on ordinary photos holds (clean top-1 changed by -1.1, i.e. one photo, and right-answer-shown by +1.1), but glare gains are about +1 point with an interval that includes zero (criterion 4 fails: only 2 of 4 conditions improved), and with the app's correction on, the candidate shows -0.6 [-2.0, +0.6] on right-answer-shown and +0.9 [-0.3, +2.3] on confident-wrong, so criterion 5 is not met either, though neither difference is reliably different from zero. I did not call this FAIL because no interval lies wholly on the harmful side. Either way the edit gives no reason to ship.
(Interpretation notes: criterion 5 is applied to the glare-mean, plus a no-rise check for confident-wrong on glare mean and clean. A FAIL verdict was defined beforehand as a safety criterion broken with its whole interval on the harmful side; PASS as all six holding; otherwise NULL.)

## Red/orange bird check

The budget names Northern Cardinal, Vermilion Flycatcher, Scarlet Tanager and Baltimore Oriole. Decided from the manifest labels, only **two** are in the test half: Northern Cardinal and Vermilion Flycatcher (Scarlet Tanager and Baltimore Oriole are in the development half). Clean photos, count of photos classified right:

| Species | Photos | Best class right: unedited | candidate | Right answer shown: unedited | candidate |
|---|---|---|---|---|---|
| Northern Cardinal | 3 | 2/3 | 2/3 | 2/3 | 2/3 |
| Vermilion Flycatcher | 3 | 2/3 | 2/3 | 2/3 | 2/3 |
| ALL | 6 | 4/6 | 4/6 | 4/6 | 4/6 |

The candidate gave exactly the same outcome as the unedited model on all six photos. That is reassuring but **too few photos to conclude anything** about red birds in general.

## Caveats

- Glare is **simulated**; real sunrise/sunset photos may behave differently.
- Small set: 87 test photos (29 species). The intervals show what this data can and cannot rule out; a +1 point effect is invisible here.
- **Best-of-15 selection.** The candidate was the most promising of 15 configurations tried on the development half, so its development gain (+1.4) is probably an overestimate. The test result (+1.1) is consistent with a true effect of about zero to one point.
- One test run only; no tuning on the test photos. (Log: `candidates/test_run_log.jsonl`, 1 run, no bug fixes or reruns.)
- A static edit cannot adapt to each photo, while the app's correction does, which is the likely reason the edit adds nothing on top of it.
- Mean margin: the edit moves it by about 0.0 to 0.1 logits, versus a deficit of 1 to 4 logits under glare.

## How to try it yourself

All paths are relative to `ml_pipeline/glare_weights/candidates/`. Use the project virtualenv (TensorFlow 2.15.1): `ml_pipeline/.venv/bin/python`.

1. **Build the candidate** from the original model (writes `BirdModel_chroma14_a05.tflite` and a `.report.json`; the original is only read):
   `./build_candidate.sh`
   Expected: 1 tensor touched, 27 weights changed, max change 0.28, output sha256 `22eb34ba...2dbd0f`; original sha256 begins `1c635b83c63650f4`.
2. **Re-run the evaluation.** Point the scripts at your copy of the photo set:
   `../../.venv/bin/python run_dev.py /path/to/glare_set` (development half, sanity check)
   `../../.venv/bin/python run_test.py /path/to/glare_set --rerun "why"` (test half; it deliberately refuses `--run-once` a second time and logs every run). Per-photo results land in `test_per_photo_results.csv`; summaries in `test_results.json`.
3. **Redraw the figure:** `../../.venv/bin/python make_examples.py /path/to/glare_set`.
4. **Try it in the app, locally and temporarily (not recommended, since there is no benefit).** Back up first: `cp ios/BioMap/BioMap/ML/Bundled/BundledBirdModel.tflite /tmp/BundledBirdModel.orig.tflite`, then copy the candidate over the bundled file (`cp ml_pipeline/glare_weights/candidates/BirdModel_chroma14_a05.tflite ios/BioMap/BioMap/ML/Bundled/BundledBirdModel.tflite`) and rebuild the app from the workspace. Note that an app already installed may prefer a model downloaded from Firestore, so use a fresh install. **To undo:** copy the backup back (`cp /tmp/BundledBirdModel.orig.tflite ios/BioMap/BioMap/ML/Bundled/BundledBirdModel.tflite`) and check `shasum -a 256` starts with `1c635b83c63650f4`. Do not commit the candidate (`*.tflite` is git-ignored in `candidates/`).

## Examples

`candidates/examples.png` shows eight test photos under simulated glare, with the top prediction and confidence from the unedited model and the candidate (no app correction), marked RIGHT or wrong. Selection rule, fixed before looking at predictions: every 4th test species alphabetically, its first photo, conditions cycling golden, veil, backlit, silhouette. They are not cherry-picked; most are wrong under glare for both models, with only the two gentler golden cases right, and the candidate changes the confidence a little but not the outcome in any of the eight.

Photo sources and licences (iNaturalist observations):
- American Avocet (American_Avocet_0.jpg, shown under golden glare): https://www.inaturalist.org/observations/155645373 , licence cc-by
- Barn Swallow (Barn_Swallow_0.jpg, shown under veil glare): https://www.inaturalist.org/observations/239048645 , licence cc-by
- Canada Goose (Canada_Goose_0.jpg, shown under backlit glare): https://www.inaturalist.org/observations/75718382 , licence cc0
- Eastern Bluebird (Eastern_Bluebird_0.jpg, shown under silhouette glare): https://www.inaturalist.org/observations/107700686 , licence cc-by
- Mourning Dove (Mourning_Dove_0.jpg, shown under golden glare): https://www.inaturalist.org/observations/330289532 , licence cc-by
- Red-tailed Hawk (Red-tailed_Hawk_0.jpg, shown under veil glare): https://www.inaturalist.org/observations/365887523 , licence cc-by
- Steller's Jay (Steller's_Jay_0.jpg, shown under backlit glare): https://www.inaturalist.org/observations/395912903 , licence cc0
- Wild Turkey (Wild_Turkey_0.jpg, shown under silhouette glare): https://www.inaturalist.org/observations/13169483 , licence cc-by
