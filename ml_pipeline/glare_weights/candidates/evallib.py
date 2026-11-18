"""Evaluation library for the Stage 3 candidate. Mirrors Stage 2's devlib.py (same simulator seeds, same app correction,
same 30/70 blend, same metrics) but works on either split and keeps per-photo bookkeeping.
Scripts live here; the photo set is passed in as a path (images are only read via PIL)."""
import pbshim  # noqa: F401  (must come before tensorflow)
import sys, json, zlib, os
import numpy as np
HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "../../.."))
sys.path.insert(0, os.path.join(REPO, "ml_pipeline/glare_eval"))
import glare_lib as G
import tensorflow as tf

ORIG = os.path.join(REPO, "ios/BioMap/BioMap/ML/Bundled/BundledBirdModel.tflite")
CAND = os.path.join(HERE, "BirdModel_chroma14_a05.tflite")
LABELS = json.load(open(os.path.join(REPO, "ios/BioMap/BioMap/ML/Bundled/BundledBirdLabels.json")))
LIDX = {l: i for i, l in enumerate(LABELS)}
CONDS = G.CONDITIONS            # clean, golden, veil, backlit, silhouette
UNKNOWN = 964
SYSTEMS = ["unedited", "unedited+corr", "candidate", "candidate+corr"]


def split_items(setdir, split):
    items = json.load(open(os.path.join(setdir, "manifest.json")))
    sp = sorted({i["label"] for i in items})
    keep = {s for k, s in enumerate(sp) if k % 2 == (0 if split == "dev" else 1)}
    return [i for i in items if i["label"] in keep]


def build_inputs(setdir, items):
    """Rows are photo-major, 5 conditions per photo. X0 = simulated photo, XC = app's adaptive correction of it."""
    X0, XC, truth, cond, photo = [], [], [], [], []
    for pi, it in enumerate(items):
        x = G.load224(os.path.join(setdir, it["file"]))
        for ci, c in enumerate(CONDS):
            y = G.simulate(x, c, zlib.crc32(f"{it['file']}|{c}".encode()))
            X0.append(y.astype(np.float32)); XC.append(G.adaptive(y).astype(np.float32))
            truth.append(LIDX[it["label"]]); cond.append(ci); photo.append(pi)
    return dict(X0=np.stack(X0), XC=np.stack(XC), truth=np.array(truth), cond=np.array(cond), photo=np.array(photo))


def run_model(path, X):
    it = tf.lite.Interpreter(model_path=path, num_threads=4); it.allocate_tensors()
    i = it.get_input_details()[0]["index"]; o = it.get_output_details()[0]["index"]
    P = np.empty((len(X), len(LABELS)), np.float32)
    for k, x in enumerate(X):
        it.set_tensor(i, x[None]); it.invoke(); P[k] = it.get_tensor(o)[0]
    return P


def metrics(P, truth):
    top = P.argmax(1); conf = P.max(1); ok = top == truth
    lp = np.log(P + 1e-12); n = np.arange(len(P))
    t = lp[n, truth]; o = lp.copy(); o[n, truth] = -1e9
    return dict(top1=ok.astype(float), shown=(ok & (conf >= 0.5)).astype(float),
                wrong=((~ok) & (conf >= 0.5) & (top != UNKNOWN)).astype(float), margin=t - o.max(1),
                top=top, conf=conf)


def evaluate_all(inp, orig=ORIG, cand=CAND):
    """Returns {system: metrics}, plus sanity info (finite, max |sum(p)-1|)."""
    out, info = {}, {}
    for name, path in (("unedited", orig), ("candidate", cand)):
        P0 = run_model(path, inp["X0"]); PC = run_model(path, inp["XC"])
        out[name] = metrics(P0, inp["truth"]); out[name + "+corr"] = metrics(0.3 * P0 + 0.7 * PC, inp["truth"])
        info[name] = dict(finite=bool(np.isfinite(P0).all() and np.isfinite(PC).all()),
                          max_psum_err=float(max(np.abs(P0.sum(1) - 1).max(), np.abs(PC.sum(1) - 1).max())))
    return out, info


def _per_photo(a, inp, conds):
    n = inp["photo"].max() + 1
    return a.reshape(n, len(CONDS))[:, conds]          # (photos, k)


def boot(d_rows, inp, conds, nb=2000, seed=0):
    """Paired bootstrap over PHOTOS of the mean (over the chosen conditions) of d_rows (per-row differences)."""
    per = _per_photo(d_rows, inp, conds).mean(1)
    rng = np.random.default_rng(seed)
    bs = np.array([per[rng.integers(0, len(per), len(per))].mean() for _ in range(nb)])
    return float(per.mean()), float(np.percentile(bs, 2.5)), float(np.percentile(bs, 97.5))


def mean_cond(a, inp, c):
    return float(_per_photo(a, inp, [c]).mean())
