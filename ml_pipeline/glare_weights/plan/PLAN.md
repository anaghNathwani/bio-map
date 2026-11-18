# Stage 2 plan: weight edits for glare robustness

All numbers: development split only (30 species, 90 photos x 5 conditions, simulated glare). The test split was never opened.
Scripts in this directory: tflite_edit.py, apply_edits.py, devlib.py, exp.py, fam.py, ci.py, selftest.py, dwcheck.py, inspect_stem.py.
configs_log.jsonl = running log of configurations tried (19 lines, 15 unique; duplicates are re-runs after an interrupted job).

## Recommendation: ship NO weight edit

No candidate improves glare accuracy beyond what the dev set can resolve, and none improves on the app's existing correction.
Every top1 / shown-right interval below includes zero.

## A. Editing mechanism (TESTED)
- `tflite_edit.py` parses the flatbuffer with the TF object API, replaces the data buffer of a named constant tensor and re-serialises.
- No-op round trip: output is byte-for-byte identical (sha256 1c635b83...a6114, 13,871,472 bytes); all 418 buffers equal; max abs output diff 0.0 on 65 dev rows.
- Stem bias (tensor 1, float32, exactly editable): shifting ch14 by -0.5 changed only ch14 output (0 change elsewhere).
- Stem weights (tensor 54, shape [32,3,3,3], float32): a QUANTIZE op re-quantises them at run time with scale 0.010053, zero point 165, range [-1.659, +0.905].
  Off-grid change of 0.3 step: rounded away (0 effect). Value 3.0: clipped to 0.905. Edit changes ch14 as predicted; other channels unchanged.
- Pitfalls: check buffer sharing (none for tensors 1, 54, 56); do not touch quantisation metadata or activation ranges; the conv input is float
  (x*2-1), only weights and outputs are fake-quantised; the first depthwise weights (tensor 56) have a very coarse step (scale 1.143).

## B/C. Candidates (TESTED, dev, n=90 photos x 5 conditions). Baseline raw / with app correction (w70):
shown-right clean 59 / 59, glare mean 31.9 / 38.6; wrong-shown clean 9 / 10, glare mean 17.2 / 13.9.

| Candidate (weights changed) | glare shown-right vs unedited (raw), 95% CI | with app correction (w70) | clean shown-right |
|---|---|---|---|
| stem bias ch14 -0.25/-0.5/-1.0 (1 of 32 biases) | -1.0..+0.9 pt (-1.0: +0.8 [-1.1,+3.1]) | +0.6 [-0.6,+1.7] | 0 [-3.3,+3.3] |
| stem bias ch21 +0.5; ch14 -0.5 & ch21 +0.5 | +0.6 / +1.7 pt | -0.1 / 0.0 | -0.0 / -1 |
| chroma damp ch14 alpha .5 (27 stem weights) | +1.4 [0.0,+2.8] | +0.8 [-0.6,+2.2] | +1.1 [0,+3.3] |
| chroma damp ch14 alpha 1.0 | +0.3 | -0.3 | +1.1 |
| chroma damp 7 colour channels, alpha .5 / 1.0 | +0.3 / -3.3 | -0.8 / -9.4 | -2 / -17 (broken) |
| warm-direction projection ch14 alpha 1.0 | +0.8 [-2.2,+3.9] | -0.3 [-2.2,+1.4] | -1.1 [-4.4,+2.2] |
| warm projection 7 ch alpha 1 / all 32 alpha .5 | -6.6 / -3.8 | -12.8 / -5.8 | -23 / -8 (broken) |
| first depthwise weights from ch14 x0.5 (=0; 5 taps) | +1.9 [-0.6,+4.4] | +0.6 [-0.8,+1.9] | -3.3 [-7.8,+1.1] |
| depthwise ch14,21 x0.5 | +0.3 | 0.0 | -1.1 |

Findings:
- Gains are 0 to +2 points, every top1/shown interval includes 0 (damp14 .5 raw glare shown [0.0,+2.8] is the closest and only touches 0).
  Mean true-class margin does rise by 0.07 to 0.27 logits (interval excludes 0), but the gap to fix is 1 to 3.4 logits, so outcomes barely change.
- Edit + app correction is never clearly better than the correction alone (+0.0 to +0.8 pt, intervals include 0).
- Anything touching all seven colour channels destroys clean accuracy (69 -> 50-52 top1): they are the model's colour representation.
- Dead stem channels (11): TESTED weights only: their first-depthwise weights are large (L1 up to 438) and not designed for any new signal. A 3x3 stride-2
  RGB stem filter could in principle build a colour detector, but its downstream effect would be arbitrary, so I judge it not worth trying (hypothesis, untested).
- Deeper-layer boost (family 3): NOT tested; no layer-specific evidence from Stage 1 and projection ranges are +-15..40.
- Head temperature (sharpening) would raise shown-right but also confident-wrong: calibration, not robustness (not tested).
- Configurations tried: 15 unique plus baseline (plus 4 duplicate re-runs). The best-looking is therefore a selection from 15 and should be discounted.

## D. Safety budget proposed for any future candidate (noise from n=90: a 1-photo change = 1.1 pt per condition, clean CI half-width ~3.3 pt)
- clean top1 and shown-right drop <= 2 pt (point estimate) and CI lower bound > -5 pt; clean wrong-shown must not rise.
- Glare shown-right improved in >= 3 of 4 conditions, and glare-mean gain CI lower bound > 0.
- Edit + app correction not worse than correction alone (CI lower bound >= -1 pt on shown, wrong not higher).
- Outputs finite, probabilities sum to 1.
- Test-split extras: same metrics once; red/orange subset (Northern Cardinal, Vermilion Flycatcher, Scarlet Tanager, Baltimore Oriole, whichever fall in the odd split; check the manifest labels, not the images) clean top1 must not fall.
No tested candidate meets the gain criterion.

## E. Efficiency / reversibility
`apply_edits.py ORIGINAL OUT recipe.json` writes a patched copy, a `.report.json` (source and output sha256, tensors touched, weights changed, max change).
Example recipe: `recipe_example.json` (1 bias changed, max change 1.0). Zero inference cost; original untouched; rollback = keep the original.

## F. Stage 3 marching orders
1. Default: do not build or ship an edit; report this null result.
2. If the orchestrator wants a documented confirmation anyway: pre-register ONE candidate (chroma damp ch14 alpha 0.5, the only one with a clean-safe glare gain whose interval touches 0), evaluate it once on the test split with the D criteria, and expect to find nothing detectable (the dev gain is about 1 pt, below the 177-photo noise).
3. Stop conditions: any clean drop beyond budget, any wrong-shown rise, or glare-mean CI including 0 -> report null and ship nothing.
Better lever (hypothesis): the existing pre-processing correction already gives +7 pt glare shown-right; further gains probably need real glare photos or training, not a static edit.

## Uncertain
Simulated glare only; n=90; static edits cannot be image-dependent; no test of deeper layers; selection from 15 configurations.
