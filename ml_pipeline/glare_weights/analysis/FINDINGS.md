# Stage 1 findings (weights + dev-split activations; supersedes the earlier partial note)

BLOCKER: the labelled set `.../scratchpad/glare_set` (manifest.json + images) does not exist in this session
(scratchpad dir for session a59f9319 is empty; no glare_set anywhere searched). I did not re-download it (needs user
permission) and loaded no images at all (dev or test). So sections C, D (activation parts), E and any forward-pass
hypothesis tests were NOT done. Everything below is read from weights. Scripts: a_arch.py, a2.py, b_first_layer_head.py.

## A. Architecture (evidence: direct tensor read)
- TFLite file is NOT plain float: it is quantization-aware-trained fake-quant. Weights are float32 but sit on an 8-bit grid
  (first-layer step ~0.0101); there are 116 QUANTIZE/DEQUANTIZE pairs, so every activation is also rounded to uint8
  with a fixed range (the ReLU6 clip lives in those ranges). 303 ops: 35 CONV_2D, 17 DEPTHWISE, 10 ADD (residual),
  AVERAGE_POOL, RESHAPE, FULLY_CONNECTED (1280 -> 965, bias 965), SOFTMAX.
- Input preprocessing is inside the graph: x*2.0 - 1.0 (ops 0,1; constants 2.0 and 1.0), so the first conv sees [-1,1],
  not 0..1 as the brief assumed.
- BN is folded (tensor names ".../Conv2D_Fold", "BatchNorm_Fold/bias"). Stem conv: 32x3x3x3, stride 2.
- Head: avgpool -> 1280 features -> FC; background class = index 964 "Unknown / Not a Bird".

## B. First layer (n=32 filters)
- 11 of 32 stem filters (CORRECTION: earlier note said 14; measured dead share is 34.4% = 11/32) are exactly zero-weight with negative bias (ch 1,2,6,7,8,9,10,11,15,19,30...), i.e. dead for every input
  (output = constant 0 after ReLU). So only ~18 channels carry signal; editing dead channels' bias/weights is a possible
  "free" site, but no evidence yet that they matter.
- Colour-opponent channels are strong: per-filter colour-sums (R,G,B over 3x3): ch14 (3.69,-1.02,-2.76) red-vs-blue,
  ch0 (-1.62,2.65,-1.02) green, ch12 (1.85,-1.73,-0.12) red-green, ch16 (1.43,-3.31,1.85) magenta-green,
  ch31 (-0.44,1.81,-1.36) green-blue, ch21 (-2.65,0.8,-0.11) bias +2.64, ch24 (-1.18,.48,.69).
  About 7 channels have |R-B| colour-sum > 0.5; many others are near zero-sum (edge/texture).
- Exact hypothetical uniform shift (in 0..1 space, pre-activation change = 2*sum(W)·d): warm cast d=(+.15,0,-.2):
  mean |dpre| 0.178 over 32 ch, max 2.21 (ch14, the red-minus-blue filter), 4 channels move >0.5. Brightness +0.2 on all
  channels: mean 0.071, max 0.78. So a warm cast hits mainly ch14/ch21/ch0/ch12 (colour-opponent) and a brightness shift
  hits mostly ch0/ch16/ch31/ch21 (green-weighted). (Uniform-shift only; real images not tested.)

## D (weights only). Head
- Background class 964 has the LARGEST bias (4.95; next is Mallard 2.62; mean 0.016, std 0.41) and the LARGEST weight norm
  (3.02 vs mean 2.01, std 0.27). So any drop in true-class evidence (feature magnitudes shrinking) makes background the
  natural winner: its bias is a ~2.3-logit head start over every species. HYPOTHESIS (untested): under glare the
  "Not a Bird"/low-confidence outcome dominates. Next-highest-bias species (Mallard, Red-tailed Hawk, Great Blue Heron,
  Great Egret, Canada Goose, House Finch, Turkey Vulture) are plausible wrong-answer attractors (untested).
- Class-mean weight vector is small (norm 0.10 vs per-class 2.0), so no obvious large common-mode direction in the head.
  Head SVD is flat (top-1 5-component energy 7%), no low-rank structure to damp.

## Not determined
Activation drift per layer (C), where the margin collapses (D), per-condition failure typology (E), actual attractors.
Need the glare_set (or permission to refetch dev species only via fetch_set.py).

## F. Candidate sites (hypotheses from weights only, all untested)
1. Stem conv colour weights / bias of ch14, ch21, ch0, ch12 (largest warm-cast response): static re-weighting would also
   change clean photos; risk high for red birds (cardinal) since ch14 is the red-blue detector.
2. Head bias of index 964 (reduce its +2.3 lead): affects clean photos' confidence on hard cases and non-bird rejection.
3. Dead stem channels: could be repurposed but no evidence of benefit.
Given the QAT grid, any edit must be re-snapped to the 8-bit grid / activation ranges or it will be quantized away or clipped.


## UPDATE: dev-split data analysis (90 images = 30 even-index species; glare SIMULATED; scripts c_collect.py, c_analyze.py -> c_out.txt, f_stem_test.py)
Input path: graph does x*2-1 internally (MUL 2.0, SUB 1.0) then QUANTIZE; stem sees [-1,1].
Outcomes (n=90/cond): clean top1 .69 shown-right .59 conf<.5 .30 bg964 wins .03 | golden .52/.46/.37/.03 | veil .44/.28/.47/.09 |
backlit .48/.41/.37/.06 | silhouette .23/.13/.51/.30. Wrong-and-shown (>=.5, not bg): clean .09, golden .16, veil .18, backlit .18, silh .18.
True-class logit margin (true - best other): clean +1.22, golden -0.27, veil -1.21, backlit -1.05, silh -3.40.
Drift: stem channels mean shift (relative L2 vs clean, post-activation) .58-.68 already at layer 4; stays .26-.44 in ReLU6 layers; pooled .77/.91/.86/1.14.
Drift appears at the very first layer (ch14 +1.34..1.75 mean, ch21 -0.7..-1.04, ch12 +.33..+.40, matching the weight-only prediction) and is
carried, not growing monotonically; silhouette is worst at every depth. Saturation at ReLU6 cap is tiny (<=0.35% of positions; depthwise 0.18% clean -> 0.25% silh).
Dead channels: stem 11/32 always; later layers 0-1% (layer 256 expand: 1% clean-always-zero, 0.7-0.9 under glare). Saturation/starvation is NOT the mechanism.
Head: true-class logit sum falls 6.96 -> 6.04/5.23/5.47/3.83 (gold/veil/back/silh) while mean pooled feature RISES (.138 -> .157-.165) and max logit stays ~9: features become more diffuse, not suppressed; true evidence in top-15 true-class channels falls to 0.74/0.63/0.78/0.59 of clean sum.
Margin collapse is therefore in the features (head is a fixed linear map, nothing else to attribute); mid/late features lose class-specific channels.
Hypothesis tests (head-only, in memory): H1 lowering bg964 bias by 1..4.95 changes top1 by at most +0.03 (silh .23->.26, veil .44->.46) and shown-right not at all (veil .28, silh .13): NOT supported as a fix; bg wins 27 of 69 silhouette errors but true class is rarely 2nd. H2 flattening species biases hurts clean (top1 .69->.62 at k=1, shown .58->.48): NOT supported. Wrong predictions are diffuse (no dominant attractor): silhouette wrong=69: bg 27, Northern Flicker 4, House Sparrow 2; other conditions bg 3-8, Downy Woodpecker 3, Northern Flicker 3, House Finch 2-3, House Sparrow 2-5. Mean bias of wrong predictions 0.98-2.22 vs 0.016 population (weakly supports bias-prior attractors but counts are tiny).
Stem-bias edit test could not be run: in-place set_tensor on constants crashes (SIGBUS, mmap read-only); would need a patched copy of the flatbuffer.
Quantisation: stem weights on a 0.0101 grid (per-tensor), stem output range 0..6.0 (scale ~0.0235); head output has own range; ADD/project conv ranges are linear +-15..40 (e.g. layer 44 +-36, 47 39). A bias edit is exactly representable only if bias is float (bias tensors are float32 here, not quantised -> exact); weight edits must be re-snapped to 0.0101 multiples; changing weight magnitude beyond the tensor max/min changes scale (unsafe); activation ranges are stored in QUANTIZE ops and must not be changed by edits.
