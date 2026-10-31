"""Sunrise/sunset glare: a synthetic glare simulator and candidate pre-corrections for the photo classifier.

Everything here works on the same 224x224 float RGB (0..1) array the app feeds BirdClassifier, in plain numpy
with no learned parts, so each correction can be mirrored one-to-one in Swift (ios/.../ML/GlareCorrector.swift)
and checked against these numbers.

The simulator is a stand-in for real glare photos (there is no labelled real-glare set to measure against), so
treat results as "does this help against the usual sunrise/sunset failure modes", not as field accuracy.
"""
import numpy as np
from PIL import Image

SIDE = 224


def load224(path):
    """Mirror of BirdClassifier's preprocessing: aspect-fill centre square, resize to 224."""
    img = Image.open(path).convert("RGB")
    w, h = img.size
    s = min(w, h)
    img = img.crop(((w - s) // 2, (h - s) // 2, (w - s) // 2 + s, (h - s) // 2 + s)).resize((SIDE, SIDE), Image.BILINEAR)
    return np.asarray(img, dtype=np.float32) / 255.0


def lum(x):
    return 0.2126 * x[..., 0] + 0.7152 * x[..., 1] + 0.0722 * x[..., 2]


_yy, _xx = np.mgrid[0:SIDE, 0:SIDE].astype(np.float32) / (SIDE - 1)


def _blob(cx, cy, sigma):
    return np.exp(-((_xx - cx) ** 2 + (_yy - cy) ** 2) / (2 * sigma ** 2))[..., None]


# --------------------------------------------------------------------------- simulation
def warm_cast(x, s):
    """Low sun: orange cast, a touch darker."""
    return np.clip(x * np.array([1.0 + 0.35 * s, 1.0 + 0.02 * s, 1.0 - 0.50 * s], np.float32) * (1 - 0.08 * s), 0, 1)


def veiling_glare(x, rng, strength):
    """A sun in or just outside the frame: warm-white veil radiating from it, washing out contrast."""
    cx, cy = rng.uniform(0.15, 0.85), rng.uniform(-0.1, 0.35)
    g = _blob(cx, cy, rng.uniform(0.35, 0.6))
    glow = np.array([1.0, 0.88, 0.65], np.float32)
    out = x * (1 - strength * g) + glow * strength * g
    return np.clip(out * (1 - 0.15 * strength) + 0.15 * strength * glow, 0, 1), (cx, cy)


def flare_ghosts(x, sun, rng, strength):
    """Soft ghost discs along the line from the sun through the frame centre (internal lens reflections)."""
    out = x.copy()
    cx, cy = sun
    for t in rng.uniform(0.35, 1.6, size=3):
        gx, gy = cx + (0.5 - cx) * t * 2, cy + (0.5 - cy) * t * 2
        rad = rng.uniform(0.04, 0.12)
        d = np.sqrt((_xx - gx) ** 2 + (_yy - gy) ** 2)[..., None]
        disc = np.clip(1 - (d / rad) ** 4, 0, 1)
        out = out + disc * strength * rng.uniform(0.2, 0.45) * np.array([1.0, 0.8, 0.55], np.float32)
    return np.clip(out, 0, 1)


def backlight(x, k_subject, bg_gain, rng):
    """Exposed for a bright sky: subject underexposed, background blown out toward warm white."""
    ox, oy = rng.uniform(0.4, 0.6), rng.uniform(0.4, 0.6)
    subject = np.clip(_blob(ox, oy, rng.uniform(0.2, 0.28)) * 1.6, 0, 1)         # soft central mask
    gain = subject * k_subject + (1 - subject) * bg_gain
    sky = (1 - subject) * np.array([0.25, 0.17, 0.08], np.float32)
    return np.clip(x * gain + sky, 0, 1)


CONDITIONS = ["clean", "golden", "veil", "backlit", "silhouette"]


def simulate(x, condition, seed):
    rng = np.random.default_rng(seed)
    if condition == "clean":
        return x
    if condition == "golden":          # the mild, most common case: warm cast + a little veil
        y = warm_cast(x, rng.uniform(0.6, 1.0))
        y, _ = veiling_glare(y, rng, rng.uniform(0.15, 0.3))
        return y
    if condition == "veil":            # sun in frame: strong veil + flare ghosts
        y = warm_cast(x, rng.uniform(0.4, 0.8))
        y, sun = veiling_glare(y, rng, rng.uniform(0.45, 0.7))
        return flare_ghosts(y, sun, rng, rng.uniform(0.5, 1.0))
    if condition == "backlit":         # subject against a bright sky
        y = backlight(x, rng.uniform(0.35, 0.55), rng.uniform(1.6, 2.2), rng)
        return warm_cast(y, rng.uniform(0.4, 0.8))
    if condition == "silhouette":      # severe: subject nearly black against blown sky
        y = backlight(x, rng.uniform(0.12, 0.25), rng.uniform(2.2, 3.2), rng)
        return warm_cast(y, rng.uniform(0.6, 1.0))
    raise ValueError(condition)


# --------------------------------------------------------------------------- measurements
def stats(x):
    """The cheap numbers used to decide whether a photo looks glare-affected."""
    y = lum(x)
    c = SIDE // 2
    r = int(SIDE * 0.3)
    centre = y[c - r:c + r, c - r:c + r]
    mask = np.ones_like(y, bool)
    mask[c - r:c + r, c - r:c + r] = False
    border = y[mask]
    bm = mask[..., None]
    border_rgb = x[mask]
    return {
        "warmth": float(x[..., 0].mean() / max(x[..., 2].mean(), 1e-4)),
        "border_warmth": float(border_rgb[:, 0].mean() / max(border_rgb[:, 2].mean(), 1e-4)),   # background only: a red bird doesn't count
        "range": float(np.percentile(y, 99) - np.percentile(y, 1)),                              # flat = veiled
        "centre_med": float(np.median(centre)),
        "border_med": float(np.median(border)),
        "backlight": float(np.median(border) - np.median(centre)),
        "clipped": float((y > 0.95).mean()),
        "dark_channel": float(_minfilter(x.min(axis=2), 7).mean()),
    }


# --------------------------------------------------------------------------- corrections
def _minfilter(a, k):
    p = k // 2
    pad = np.pad(a, p, mode="edge")
    win = np.lib.stride_tricks.sliding_window_view(pad, (k, k))
    return win.min(axis=(-1, -2))


def gray_world(x, strength=0.7, lo=0.7, hi=1.45):
    """Remove the orange cast: scale channels toward equal means (clamped, partial)."""
    m = x.reshape(-1, 3).mean(0)
    gains = np.clip(m.mean() / np.maximum(m, 1e-4), lo, hi)
    gains = 1 + strength * (gains - 1)
    return np.clip(x * gains, 0, 1)


def dehaze(x, omega=0.6, patch=7, t0=0.4):
    """Dark-channel-prior dehazing: undoes the veil a bright light source lays over the frame."""
    dark = _minfilter(x.min(axis=2), patch)
    n = max(1, int(0.001 * dark.size))
    idx = np.argsort(dark.ravel())[-n:]
    A = np.clip(x.reshape(-1, 3)[idx].mean(0), 0.55, 1.0)
    t = np.clip(1 - omega * _minfilter((x / A).min(axis=2), patch), t0, 1.0)
    return np.clip((x - A) / t[..., None] + A, 0, 1)


def shadow_lift(x, target=0.42, knee=0.82):
    """Lift an underexposed subject and soften blown highlights, preserving hue (gain applied to RGB)."""
    y = lum(x)
    c = SIDE // 2
    r = int(SIDE * 0.3)
    med = float(np.median(y[c - r:c + r, c - r:c + r]))
    if med >= 0.38:
        return x
    g = np.clip(np.log(target) / np.log(max(med, 0.02)), 0.4, 1.0)   # gamma < 1 brightens
    y2 = np.power(np.maximum(y, 1e-4), g)
    over = np.maximum(y2 - knee, 0)
    y2 = y2 - 0.6 * over                                                # soft highlight roll-off
    gain = np.clip(y2 / np.maximum(y, 1e-4), 0.0, 4.0)[..., None]
    return np.clip(x * gain, 0, 1)


def auto_levels(x, lo_p=1.0, hi_p=99.0):
    """Stretch each channel's 1st..99th percentile to 0..1 (restores contrast flattened by veiling glare)."""
    out = np.empty_like(x)
    for ch in range(3):
        lo, hi = np.percentile(x[..., ch], [lo_p, hi_p])
        out[..., ch] = np.clip((x[..., ch] - lo) / max(hi - lo, 0.15), 0, 1)
    return out


# Gates (round numbers read off the clean-vs-glare distributions of the measurements above, not tuned on accuracy).
WARM_BORDER = 1.45      # background R/B: clean p90 1.48 vs glare p10 1.35-1.64
VEIL_RANGE = 0.65       # flat luminance range ...
VEIL_WARM = 1.25        # ... on a warm background means a veiling sun
BACKLIGHT = 0.25        # border brighter than the subject by this much (clean p90 0.14, backlit p10 0.30)
SUBJECT_DARK = 0.40     # and the subject is actually dark


def adaptive(x, return_flags=False):
    """Correct only what the photo's own measurements say is wrong; leave ordinary photos untouched."""
    s = stats(x)
    y, flags = x, []
    if s["border_warmth"] > WARM_BORDER:
        y = gray_world(y); flags.append("warm")
    if s["range"] < VEIL_RANGE and s["border_warmth"] > VEIL_WARM:
        y = auto_levels(y); flags.append("veil")
    if s["backlight"] > BACKLIGHT and s["centre_med"] < SUBJECT_DARK:
        y = shadow_lift(y); flags.append("backlit")
    return (y, flags) if return_flags else y


PIPELINES = {
    "none": lambda x: x,
    "gray_world": gray_world,
    "dehaze": dehaze,
    "shadow_lift": shadow_lift,
    "auto_levels": auto_levels,
    "wb+lift": lambda x: shadow_lift(gray_world(x)),
    "wb+dehaze+lift": lambda x: shadow_lift(dehaze(gray_world(x))),
    "full": lambda x: auto_levels(shadow_lift(dehaze(gray_world(x)))),
    "adaptive": adaptive,
}
