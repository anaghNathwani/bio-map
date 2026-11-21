# Sunrise / sunset glare by editing weights (an experiment)

This file records an experiment in "weight-space programming": instead of retraining the photo classifier, read its weights,
work out by reasoning where it breaks in sunrise and sunset light, and edit a small number of weights directly, with no
gradient descent. It is run as three stages, each by its own agent with an orchestrator in charge, and each stage appends its
conclusion below.

Related: the pre-processing glare correction that already ships (`ios/BioMap/BioMap/ML/GlareCorrector.swift`) and how it was
measured (`docs/ML_PIPELINE.md`, "Sunrise / sunset glare"; `ml_pipeline/glare_eval/`).

## The idea we're borrowing

The post [Sparks of Weight-Space Programming](https://rikiyat.github.io/blog/weight-space-programming/) (Takehi, Teoh, Zhang,
Khattab; MIT CSAIL, 2 November 2026) describes a general-purpose language model reading a network's weights directly,
diagnosing what its parts compute, and editing them around a plain-language goal, "not through an optimizer". Points that matter
here (paraphrased; the post's own wording of its method is brief and contains no code):

- Edits were small and targeted. In its main result, one direction was subtracted from 64 output columns in each of two layers
  of a 0.8B-parameter model (131,072 weights, about 0.016%), and the model's maths scores rose sharply.
- Some edits were guided only by reading weights. Others used a limited number of forward passes on **practice** data that was
  kept separate from the evaluation data, keeping an edit only if it helped.
- It reports its results as early, and reports no regression checks or safety guidance. One small model it tried (Gemma 270M)
  showed no gain: editing can remove an obstacle but not add an ability the model lacks.

**What differs here.** Our model is a small convolutional image classifier (Google AIY Birds V1, a MobileNetV2-style network),
not a language model, and it was exported to TensorFlow Lite, which folds batch-normalisation into the convolution weights. So
we treat the post as a method, not a recipe, and we add the safety checks the post doesn't describe.

## Ground rules for every stage

- **No gradient descent and no training.** Only reading, reasoning and direct edits, with a small number of forward passes on the
  development split to check ideas.
- **Two splits, fixed in advance.** Species are sorted alphabetically from the evaluation set's manifest
  (`ml_pipeline/glare_eval/`): even positions are the **development** split (free to analyse and tune on), odd positions are the
  **test** split (sealed: touched only once, at the end, to report results). The test split is also never used to choose an edit.
- **Safety budget.** An edit is only acceptable if accuracy on ordinary (clean) photos does not drop meaningfully and confident
  wrong answers do not increase; both are checked on the development split while tuning and on the test split at the end.
- **Nothing ships.** The bundled model (`ios/BioMap/BioMap/ML/Bundled/BundledBirdModel.tflite`) is never modified. Candidates
  live in `ml_pipeline/glare_weights/` for review.
- **Caveat that applies to everything below:** glare in the evaluation set is simulated (there is no labelled set of real sunrise
  or sunset photos), and the set is small (177 photos, 59 species). Results show direction, not field accuracy.

| Stage | Agent | Output |
|---|---|---|
| 1. Analysis | Reads the weights and activations and works out where and why the model fails in low-sun conditions | "Stage 1" below |
| 2. Planning | Works out the most efficient and safest set of edits | "Stage 2" below |
| 3. Implementation | Applies the plan, evaluates it, and leaves a candidate ready to review | "Stage 3" below |

---

## Stage 1: where the model fails in low-sun light (analysis agent)

Method: the agent read the model's tensors directly, did linear algebra on them, then checked its ideas with forward passes on the
**development split only** (30 species, 90 photos, five conditions each). Glare is simulated. No test-split photo was opened.
Scripts and full tables: `ml_pipeline/glare_weights/analysis/` (`FINDINGS.md`, `c_out.txt`).

**The model, as found.** It is a MobileNetV2-style network (303 operations, 35 convolutions, 17 depthwise convolutions, one
1280 → 965 classifier) exported as *quantisation-aware* TensorFlow Lite: weights are float numbers sitting on an 8-bit grid, and
every activation is rounded to 8 bits with a fixed range (116 quantise/dequantise pairs). The input is rescaled inside the graph
(`x*2 − 1`). Batch-norm is folded into the convolutions. Class 964 is "Unknown / Not a Bird". Any edit has to respect those grids
and ranges or it will be rounded away or clipped.

**What the agent found (dev split, n = 90 photos)**

| | Clean | Golden | Veil | Backlit | Silhouette |
|---|---|---|---|---|---|
| Best class correct | 69% | 52% | 44% | 48% | 23% |
| Correct suggestion shown (≥ 0.5 confidence) | 59% | 46% | 28% | 41% | 13% |
| Confidently wrong | 9% | 16% | 18% | 18% | 18% |
| Mean margin of the true class over the best rival (logits) | +1.22 | −0.27 | −1.21 | −1.05 | −3.40 |

1. **The loss happens in the features, not in the final classifier.** The classifier is a fixed linear map with no structure to
   exploit. Under glare, average feature strength actually rises, but the channels that carry class-specific evidence fade (the top
   15 evidence channels drop to 59–78% of their clean strength). The features get diffuse rather than suppressed.
2. **The drift starts at the very first layer and is carried forward, not amplified.** The stem's few colour-opponent filters
   respond to the orange cast exactly as the weights predicted: the red-minus-blue filter (channel 14) rises by 1.3 to 1.75 under
   every condition, channel 21 falls by 0.7 to 1.0, channel 12 rises by about 0.35. Only about 7 of the 32 stem filters are strongly
   colour-sensitive; 11 are dead (always zero).
3. **Saturation is not the mechanism.** Activations at the top of their range are 0.35% or fewer, and dead channels barely change.
4. **Two natural fixes for the classifier did not work.** Lowering the bias of the "Not a Bird" class (which has the highest bias in
   the model, 4.95 against 2.62 for the next) changed accuracy by at most 3 points. Flattening the species biases hurt clean
   photos (69% → 62%). The classifier has no common direction to damp.

**Failure by condition.** *Golden:* the cast shifts the colour filters, the margin falls to about zero, and mostly the model turns
confidently wrong. *Veil:* contrast loss makes correct answers lose confidence (47% fall under 0.5). *Backlit:* a brightness shift
on top of the cast; confident-wrong rises to 18%. *Silhouette:* severe; "Not a Bird" wins 30% of the time and confidence falls under
0.5 in 51%.

**Candidate edit sites, ranked** (none tested as an edit yet):

1. **Stem colour filters (channels 14, 21, 12):** counter the warm-cast response at the source. Real evidence (measured drift), but it
   is risky for clean photos of red or orange birds, because channel 14 is the red-versus-blue detector, and a weight edit is
   static where the app's pre-processing adapts to each photo. The stem bias is float and exactly editable; weights must be
   re-snapped to the 8-bit grid and stay inside the tensor's range.
2. **Mid-network class-specific channels:** the loss is here, but the data can't say which layer, and the projection layers have
   wide ranges (about ±15 to ±40) where an edit could overflow. Low confidence.
3. **"Not a Bird" bias, species-bias flattening, dead stem channels:** tested or reasoned to be not worth it.

**What this stage could not settle.** Whether any edit actually helps (the agent's in-place test crashed, because constant tensors
are read-only, so a patched copy of the file is needed); which middle layers matter; how 8-bit rounding affects small edits.
The photo set was re-downloaded for this stage after the earlier copy was lost, so its numbers differ slightly from the figures in
`docs/ML_PIPELINE.md`.

---

## Stage 2: the safest, most efficient edit (planning agent)

Method: the agent built a tool for patching the model file, tried candidate edits on the **development split only** (90 photos ×
five conditions, simulated glare), and measured each against the unedited model and against the app's existing pre-processing
correction. Plan, tools and the full log: `ml_pipeline/glare_weights/plan/` (`PLAN.md`, `tflite_edit.py`, `apply_edits.py`,
`configs_log.jsonl`).

**Recommendation: ship no weight edit.** None of the tested edits improved glare accuracy by more than the development set can
reliably detect, and none beat the correction the app already has.

**The editing mechanism works and is safe.** `tflite_edit.py` rewrites a constant tensor's data and saves a *new* file. A no-op
round trip is byte-for-byte identical to the original, and the patched file loads in TensorFlow Lite. Two things to know:
weight edits smaller than half a step of the 8-bit grid are rounded away, and values outside the tensor's range are clipped, so
`apply_edits.py` re-snaps every weight to the grid. The original model is never touched and the recipe reproduces from it.

**What was tried** (15 configurations in all; the best of 15 should be discounted, since picking a winner from many tries
overstates it). Figures are changes in "correct suggestion shown" in percentage points, with 95% intervals, averaged over the four
glare conditions. For reference, the unedited model shows 31.9% on glare and the app's correction lifts that to 38.6%.

| Edit | Weights changed | Alone | Combined with the app's correction | Verdict |
|---|---|---|---|---|
| Shift the red-minus-blue stem filter's bias (ch14, −0.25 to −1.0) | 1 | about 0 to +1.7 | +0.6 [−0.6, +1.7] | Safe, no usable gain |
| **Chroma damping of ch14 (α = 0.5)**: shrink its colour-opponent part toward its grey part | 27 (0.9% of the stem) | +1.4 [0.0, +2.8] | +0.8 [−0.6, +2.2]; clean photos 0 [−3.3, +3.3] | Best candidate, but not clearly above zero |
| Chroma damping of ch14 (α = 1.0) | 27 | +0.3 | −0.3 | No |
| Damp all 7 colour filters | about 190 | breaks clean photos (69% → 52%) | | Unsafe |
| Subtract the "warm-cast direction" (the post's style of edit) on all 32 channels | all stem | clean falls to 60% | | Unsafe |
| Boost ch14's downstream gain | 5 taps | +1.9 [−0.6, +4.4], clean −3.3 [−7.8, +1.1] | +0.6 | No |

Not tested: deeper layers (Stage 1 found no layer-specific evidence, and the ranges there are wide), and changing the output
sharpness (that changes calibration, not robustness). The 11 dead stem channels were judged not worth repurposing: each feeds
large, non-designed weights downstream.

**Why the edits can't compete.** The colour filter ch14 alone accounts for all of the small movement, and widening the edit hurts
ordinary photos. The mean margin improves by only 0.07 to 0.27 logits against a 1 to 3.4 logit deficit, so almost nothing flips.
A static edit is also the same for every photo, while the problem is photo-dependent; the app's correction adapts to each photo,
which is the likely reason it works better.

**Safety budget proposed for any edit:** clean accuracy and clean correct-suggestion rate may not fall by more than 2 points (lower
bound above −5); confidently-wrong answers on clean photos may not rise; glare must improve in at least 3 of 4 conditions with the
glare-mean interval above zero; an edit combined with the app's correction may not be worse than the correction alone; and a
one-time check on the sealed test split, including a red/orange-bird subset (cardinal, vermilion flycatcher, scarlet tanager,
Baltimore oriole), where those species fall in the test half.

**Hand-off to Stage 3:** the default is to build nothing and report the null result. To leave something to look at, build the single
pre-registered candidate (chroma damping of ch14 at α = 0.5), evaluate it **once** on the test split against the budget above, and
stop and report a null result if any clean-photo limit is broken or the glare interval includes zero. Dev-set noise is about
3.3 points either way, so any apparent gain should be read with that in mind.

---

## Stage 3: build the candidate and test it once (implementation agent)

Stage 2's default was to build nothing. To leave something to inspect, this stage built the one pre-registered candidate and tested
it **once** on the sealed test split (29 species, 87 photos), against the safety budget set in advance.

**The candidate.** Chroma damping of stem channel 14 at α = 0.5: the filter that detects "red versus blue" keeps its
brightness-pattern part and has its colour-difference part halved. That is 27 of the 864 stem weights, changed by at most 0.28 and
re-snapped to the 8-bit grid. The recipe is `ml_pipeline/glare_weights/candidates/recipe_chroma14_a05.json`; the patched file is
`BirdModel_chroma14_a05.tflite` there. The bundled model was never touched (its checksum was recorded before and after and I
re-checked it). Before the test, the agent reproduced Stage 2's development-split numbers to the decimal.

**Result on the test split (correct suggestion shown, percent; simulated glare):**

| System | Clean | Golden | Veil | Backlit | Silhouette | Glare mean |
|---|---|---|---|---|---|---|
| 1. Unedited model | 57.5 | 47.1 | 35.6 | 36.8 | 8.0 | 31.9 |
| 2. Unedited + the app's correction | 57.5 | 52.9 | 44.8 | 37.9 | 20.7 | 39.1 |
| 3. Candidate alone | 58.6 | 49.4 | 37.9 | 36.8 | 8.0 | 33.0 |
| 4. Candidate + the app's correction | 58.6 | 52.9 | 43.7 | 39.1 | 18.4 | 38.5 |

Differences with 95% intervals (paired bootstrap, 87 photos, percentage points): the candidate alone adds **+1.1 [−0.3, +2.6]** on
the glare average, and the candidate on top of the app's correction is **−0.6 [−2.0, +0.6]** compared with the correction alone.
Both intervals include zero. Confidently-wrong answers on clean photos did not change.

**Safety budget:** clean accuracy within limits (PASS), clean correct-suggestion rate (PASS), clean confidently-wrong (PASS),
finite outputs (PASS). **FAIL:** only 2 of 4 glare conditions improved and the glare interval includes zero, and the candidate on
top of the app's correction was not reliably as good as the correction alone.

**Verdict: NULL.** The edit is safe but has no reliable effect. It was one run, with no tuning afterwards.

**Red and orange birds.** Only Northern Cardinal and Vermilion Flycatcher fall in the test split (Scarlet Tanager and Baltimore
Oriole are in the development half): six photos in all, 4 of 6 right both with and without the edit, with identical outcomes. Far
too few to conclude anything.

`ml_pipeline/glare_weights/REPORT.md` has the full tables and instructions; `candidates/examples.png` shows eight test photos
under glare with both models' answers (six of the eight are wrong for both models, and the edit changes none of them).

### What the experiment tells us

1. **A static weight edit is the wrong tool here.** Glare changes each photo differently, and the model's failure is spread across
   features rather than sitting in one place. The one place the analysis could point to (the red-versus-blue stem filter) accounts
   for only a tiny part of the loss. The app's per-photo correction is the lever that works (+7 points of correct suggestions on
   glare, in both stages' numbers).
2. **Process findings.** The weight-reading step did find real structure (which stem filters carry the colour shift, that the loss
   is in the features, that two obvious head edits don't help), and the editing tool is sound. But this is a small
   convolutional network, not the large language model in the post, and the post's own small-model test (Gemma 270M) also showed
   no gain.
3. **If we want more robustness**, the better options are real: collect real dawn and dusk photos (with consent) to build a
   proper evaluation set; fine-tune on them under the company's fine-tuning policy once there is enough labelled data; or improve
   the adaptive correction.

### Limits that apply to this whole experiment

- Glare is **simulated**. The example sheet makes the weakness visible: the backlit and silhouette photos show an obviously
  artificial dark disc around the subject, which is not what real backlight looks like. Real glare may behave differently.
- 177 photos, 59 species; one photo is worth about 1.1 points. Fifteen configurations were tried in Stage 2, so a best-of-15 gain is
  inflated.
- The photo set was lost once and re-downloaded mid-experiment (the temporary folder was cleared), so numbers from before and after
  differ slightly; the Stage 2 and Stage 3 numbers use the same re-downloaded set. One planning run was interrupted when the
  computer slept and was resumed from its saved files.

---

## What real photos showed (follow-up)

The three stages above all used *simulated* glare. To check that against reality, we built a set of **real** photos: research-grade,
openly licensed (CC0 / CC-BY / CC-BY-SA) iNaturalist observations of the 56 species the model knows, with each photo's capture time
and location turned into the sun's height at that moment (`ml_pipeline/glare_eval/solar.py`, `fetch_lowsun.py`). That gives
**1,349 photos**: 330 in daylight (sun above 35°), 238 at golden hour (3° to 10°), and **781 with the sun within 3° of the horizon**
(sunrise and sunset proper). The photos are kept outside the repository, and nothing was trained on them.

**1. The gap is real, but only right at the horizon** (the unedited model; `horizon_analysis.py`):

| Sun height | Photos | Best class right | Correct suggestion shown | Confidently wrong |
|---|---|---|---|---|
| Daylight (above 35°) | 330 | 77.3% | 68.2% | 4.5% |
| Golden hour (3° to 10°) | 238 | 78.6% | 66.8% | 4.6% |
| **Within 3° of the horizon** | 781 | **67.2%** | **58.4%** | **8.8%** |

Matched species by species (55 species), the near-horizon shortfall is **−9.6 points [−15.4, −3.6]** for the best class and
**−9.3 [−15.9, −2.0]** for the suggestion shown. Golden hour is as good as daylight, so it's the last stretch around sunrise and
sunset that hurts, and confidently-wrong answers double there.

**2. It is not the orange cast or an exposure problem.** None of the measurements the simulation was built around separates real
near-horizon photos from ordinary ones. They aren't warmer (the background's red-to-blue ratio is 1.02 against 1.14 in daylight;
cameras correct the cast themselves), their brightness is about the same (0.505 against 0.486), and none of the measurements goes
with errors inside the near-horizon group (every correlation is 0.16 or smaller). What does differ is lower colour saturation (0.20
against 0.26). The reason for the gap is unknown. Candidates we can't separate with this data: birds in flight or in silhouette,
distance, low-light camera noise and blur, and behaviour at those hours.

**3. Pre-corrections don't help real photos.** Each candidate was blended 30/70 into the model's answer, as the app does:

| Correction | Near-horizon, correct suggestion shown | Daylight photos |
|---|---|---|
| The app's glare correction (fires on 12% of near-horizon, 24% of daylight photos) | −0.4 [−1.2, +0.3] | **−1.2 [−2.4, −0.3]** |
| Shadow lift | +0.1 [−0.4, +0.6] | +0.3 [−0.6, +1.5] |
| Gamma brighten | 0.0 [−0.8, +0.8] | +0.3 [0.0, +0.9] |
| Contrast stretch on every photo | −1.5 [−3.5, +0.3] | −3.3 [−6.1, −0.9] |
| Grey-world white balance on every photo | −0.5 [−1.9, +0.9] | −1.2 [−3.3, +0.6] |

So the glare correction we shipped, which looked good against simulated glare (+7 points), does nothing where the model is weak and
slightly hurts ordinary daylight photos.

**4. Fine-tuning only the last layer doesn't fix it either** (`ml_pipeline/glare_weights/probe/head_probe.py`; gradient training
of the final layer, starting from the shipped weights and pulled back toward them; 5-fold). Holding out random photos, it gains
+3.8 / +5.2 points near the horizon, but also +3.0 / +3.3 on daylight photos, so it is fitting these 56 species, not the horizon.
Holding out whole species (the realistic test, as the app has 965) it loses 2 to 3 points, or does nothing when pulled back
harder. A real fix would need feature-level fine-tuning across many species, not a small head tweak.

### Decisions

- **The app's glare correction is switched off** (`GlareCorrector.isEnabled = false`). The code and its parity test stay, in case a
  better correction turns up. This is the one code change the experiment led to.
- **No weight edit, and no fine-tune on this data.** Neither is supported by the evidence.
- **Next step, if the near-horizon gap matters enough:** a feature-level fine-tune on thousands of real near-horizon photos covering
  many species, mixed with daylight photos to avoid forgetting, evaluated on held-out species. That suits the planned Mac mini.
  Before any training: check the photo licences (CC-BY needs attribution; CC-BY-SA's share-alike terms may reach the model) and
  update the Terms and Privacy pages if user photos are ever used.

### Limits

Research-grade photos are ones the community could identify, so the worst silhouettes are under-represented and the real gap may be
larger than measured. The photos come from other people's cameras, not phone cameras. Sun height says when a photo was taken, not
how it looks. The weakness near the horizon is real, but this experiment does not show *why*.
