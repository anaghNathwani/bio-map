"""Dev-split-only evaluation harness. Loads ONLY even-index species (alphabetical). Cache of simulated/corrected inputs
lives in the scratchpad (outside the data dir)."""
import sys, json, zlib, os, pathlib
import numpy as np
sys.path.insert(0, "/Users/anagh/important/congressional/birdmap/ml_pipeline/glare_eval")
import glare_lib as G
import tensorflow as tf
SET = "/private/tmp/claude-501/-Users-anagh-important-congressional/a59f9319-dd57-4a56-a8c8-2bbdac3ab64f/scratchpad/glare_set"
CACHE = "/private/tmp/claude-501/-Users-anagh-important-congressional/a59f9319-dd57-4a56-a8c8-2bbdac3ab64f/scratchpad/plan_cache.npz"
ORIG = "/Users/anagh/important/congressional/birdmap/ios/BioMap/BioMap/ML/Bundled/BundledBirdModel.tflite"
LABELS = json.load(open("/Users/anagh/important/congressional/birdmap/ios/BioMap/BioMap/ML/Bundled/BundledBirdLabels.json"))
LIDX = {l: i for i, l in enumerate(LABELS)}
CONDS = G.CONDITIONS


def dev_items():
    items = json.load(open(SET + "/manifest.json"))
    sp = sorted({i["label"] for i in items})
    dev = {s for k, s in enumerate(sp) if k % 2 == 0}
    return [i for i in items if i["label"] in dev]


def build_cache():
    items = dev_items()
    X0, XC, truth, cond, species = [], [], [], [], []
    for it in items:
        x = G.load224(SET + "/" + it["file"])
        for c in CONDS:
            y = G.simulate(x, c, zlib.crc32(f"{it['file']}|{c}".encode()))
            X0.append(y.astype(np.float32)); XC.append(G.adaptive(y).astype(np.float32))
            truth.append(LIDX[it["label"]]); cond.append(CONDS.index(c)); species.append(it["label"])
    np.savez(CACHE, X0=np.stack(X0), XC=np.stack(XC), truth=np.array(truth), cond=np.array(cond), species=np.array(species))


def load_cache():
    if not os.path.exists(CACHE):
        build_cache()
    return np.load(CACHE)


def run_model(path, X):
    it = tf.lite.Interpreter(model_path=path, num_threads=4); it.allocate_tensors()
    i = it.get_input_details()[0]["index"]; o = it.get_output_details()[0]["index"]
    P = np.empty((len(X), len(LABELS)), np.float32)
    for k, x in enumerate(X):
        it.set_tensor(i, x[None]); it.invoke(); P[k] = it.get_tensor(o)[0]
    return P


def per_item(P, truth):
    """arrays per item: top1, shown, wrong, margin (log-prob true minus best other)."""
    top = P.argmax(1); conf = P.max(1)
    ok = top == truth
    shown = ok & (conf >= 0.5)
    wrong = (~ok) & (conf >= 0.5) & (top != 964)
    lp = np.log(P + 1e-12)
    t = lp[np.arange(len(P)), truth]
    o = lp.copy(); o[np.arange(len(P)), truth] = -1e9
    return dict(top1=ok.astype(float), shown=shown.astype(float), wrong=wrong.astype(float), margin=t - o.max(1))


def evaluate(path, cache=None):
    """Returns dict: mode -> per-item metric arrays over all 450 (item,cond) rows. modes: raw (no correction), w70 (app)."""
    d = cache if cache is not None else load_cache()
    P0 = run_model(path, d["X0"]); PC = run_model(path, d["XC"])
    t = d["truth"]
    return {"raw": per_item(P0, t), "w70": per_item(0.3 * P0 + 0.7 * PC, t), "finite": bool(np.isfinite(P0).all() and np.isfinite(PC).all()),
            "psum": float(np.abs(P0.sum(1) - 1).max())}


def summarize(res, mode, cond):
    d = load_cache(); m = d["cond"] == cond
    r = res[mode]
    return {k: float(r[k][m].mean()) for k in ("top1", "shown", "wrong", "margin")}


def boot_diff(a, b, cond=None, species=None, nb=2000, seed=0):
    """Paired bootstrap CI of mean(a)-mean(b), resampling PHOTOS (the 90 photos), keeping the paired rows."""
    d = load_cache(); m = (d["cond"] == cond) if cond is not None else np.ones(len(a), bool)
    sp = d["species"]
    # unit = photo: rows are ordered photo-major, 5 conds per photo
    idx = np.arange(len(a)).reshape(-1, 5)  # (90,5)
    sel = idx if cond is None else idx[:, [cond]]
    diff = (a - b)[sel]  # (90, k)
    per = diff.mean(1)
    rng = np.random.default_rng(seed)
    bs = np.array([per[rng.integers(0, len(per), len(per))].mean() for _ in range(nb)])
    return float(per.mean()), float(np.percentile(bs, 2.5)), float(np.percentile(bs, 97.5))
