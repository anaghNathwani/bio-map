"""Can fine-tuning the model's final layer on real near-horizon photos close the near-horizon gap?  (a cheap feasibility probe)

Extracts each photo's pooled 1280-d feature vector and the model's original output, then trains ONLY the final linear layer
(warm-started from the shipped weights, pulled back toward them by an L2 penalty so it can't wander) with gradient descent, and
measures held-out photos two ways:
  by photo    random photos held out (species also appear in training: optimistic; the head can learn those species)
  by species  whole species held out (the honest test: the app has 965 species, we only have photos of ~56)
Nothing is shipped; this only tells us whether a bigger fine-tune is worth doing.

  python head_probe.py --sets DIR [DIR ...] --cache pooled.npz
"""
import argparse, json, pathlib, sys
import numpy as np
import tensorflow as tf

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2] / "glare_eval"))
import glare_lib as G

MODEL = pathlib.Path(__file__).resolve().parents[3] / "ios/BioMap/BioMap/ML/Bundled/BundledBirdModel.tflite"
LABELS = json.loads((MODEL.parent / "BundledBirdLabels.json").read_text())
MIN_CONF = 0.5


def extract(sets):
    it = tf.lite.Interpreter(model_path=str(MODEL), experimental_preserve_all_tensors=True)
    it.allocate_tensors()
    ops = it._get_ops_details()
    pool = [o for o in ops if o["op_name"] == "AVERAGE_POOL_2D"][0]["outputs"][0]
    fc = [o for o in ops if o["op_name"] == "FULLY_CONNECTED"][0]
    W0 = b0 = None
    inp, out = it.get_input_details()[0]["index"], it.get_output_details()[0]["index"]
    F, P, meta = [], [], []
    for d in sets:
        d = pathlib.Path(d)
        for m in json.loads((d / "manifest.json").read_text()):
            it.set_tensor(inp, G.load224(d / m["file"])[None].astype(np.float32)); it.invoke()
            if W0 is None:      # the FC weights come out of a DEQUANTIZE op, so they exist only after the first run
                W0, b0 = it.get_tensor(fc["inputs"][1]).copy(), it.get_tensor(fc["inputs"][2]).copy()
            F.append(it.get_tensor(pool).reshape(-1).copy()); P.append(it.get_tensor(out)[0].copy())
            meta.append((m["label"], m["sun_elevation"]))
    return np.array(F, np.float32), np.array(P, np.float32), meta, W0.astype(np.float32), b0.astype(np.float32)


def softmax(z):
    z = z - z.max(1, keepdims=True); e = np.exp(z); return e / e.sum(1, keepdims=True)


def train(F, y, W0, b0, lam, steps=150, lr=2e-3):
    W, b = W0.copy(), b0.copy()
    mW, vW, mb, vb = np.zeros_like(W), np.zeros_like(W), np.zeros_like(b), np.zeros_like(b)
    Y = np.zeros((len(y), W.shape[0]), np.float32); Y[np.arange(len(y)), y] = 1
    for t in range(1, steps + 1):
        P = softmax(F @ W.T + b)
        gz = (P - Y) / len(y)
        gW = gz.T @ F + lam * (W - W0); gb = gz.sum(0) + lam * (b - b0)
        for p, g, m, v in ((W, gW, mW, vW), (b, gb, mb, vb)):
            m *= 0.9; m += 0.1 * g; v *= 0.999; v += 0.001 * g * g
            p -= lr * (m / (1 - 0.9 ** t)) / (np.sqrt(v / (1 - 0.999 ** t)) + 1e-8)
    return W, b


def score(P, y, idx):
    top = P.argmax(1); conf = P.max(1)
    ok = top[idx] == y[idx]
    return dict(top1=float(ok.mean()), shown=float((ok & (conf[idx] >= MIN_CONF)).mean()),
                wrong=float((~ok & (conf[idx] >= MIN_CONF) & (top[idx] != 964)).mean()))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sets", nargs="+", required=True)
    ap.add_argument("--cache", required=True)
    a = ap.parse_args()
    cache = pathlib.Path(a.cache)
    if cache.exists():
        z = np.load(cache, allow_pickle=True); F, P0, meta, W0, b0 = z["F"], z["P"], list(map(tuple, z["meta"])), z["W0"], z["b0"]
    else:
        F, P0, meta, W0, b0 = extract(a.sets)
        np.savez(cache, F=F, P=P0, meta=np.array(meta, dtype=object), W0=W0, b0=b0)
    names = [m[0] for m in meta]; elev = np.array([float(m[1]) for m in meta])
    y = np.array([LABELS.index(n) for n in names])
    print("photos", len(y), "| warm-start check: max |softmax(head) - model output| =", float(np.abs(softmax(F @ W0.T + b0) - P0).max()))
    hz, dy = elev < 3, elev >= 35
    rng = np.random.default_rng(0)
    species = sorted(set(names)); sp_fold = {s: i % 5 for i, s in enumerate(rng.permutation(species))}
    folds = {"by photo": rng.integers(0, 5, len(y)), "by species": np.array([sp_fold[n] for n in names])}
    base = {"horizon": score(P0, y, np.where(hz)[0]), "day": score(P0, y, np.where(dy)[0])}
    print("unmodified model on all photos: horizon top1 %.1f shown %.1f | day top1 %.1f shown %.1f" % (
        100 * base["horizon"]["top1"], 100 * base["horizon"]["shown"], 100 * base["day"]["top1"], 100 * base["day"]["shown"]))
    print(f"\n{'held out':11s}{'lambda':>7s} | {'horizon top1':>16s}{'horizon shown':>16s}{'horizon wrong':>16s} | {'day top1':>14s}{'day shown':>14s}  (change vs unmodified, held-out photos only, points)")
    for scheme, fold in folds.items():
        for lam in (0.3, 3.0, 30.0):
            P1 = np.zeros_like(P0)
            for k in range(5):
                tr, te = np.where(fold != k)[0], np.where(fold == k)[0]
                W, b = train(F[tr], y[tr], W0, b0, lam)
                P1[te] = softmax(F[te] @ W.T + b)
            cells = []
            for grp in (hz, dy):
                idx = np.where(grp)[0]
                s0, s1 = score(P0, y, idx), score(P1, y, idx)
                cells.append({k: 100 * (s1[k] - s0[k]) for k in s0})
            print(f"{scheme:11s}{lam:7.1f} | {cells[0]['top1']:+16.1f}{cells[0]['shown']:+16.1f}{cells[0]['wrong']:+16.1f} | {cells[1]['top1']:+14.1f}{cells[1]['shown']:+14.1f}", flush=True)


if __name__ == "__main__":
    main()
