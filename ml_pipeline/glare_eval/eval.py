"""Measures the photo classifier on a labelled set under simulated sunrise/sunset glare, with and without corrections.

  python eval.py --set /path/to/glare_set [--pipelines none,full,...] [--json out.json]

Per condition and pipeline it reports, over the images:
  top1    the model's best class is the right species
  shown   the app would show the RIGHT species (best class right AND confidence >= 0.5, BirdClassifier.minConfidence)
  wrong   the app would confidently show a WRONG species (the failure to avoid)
Modes: "single" classifies only the corrected photo; "tta" averages the original's and the corrected photo's probabilities.
"""
import argparse, json, pathlib, sys, zlib
import numpy as np
import tensorflow as tf
import glare_lib as G

ROOT = pathlib.Path(__file__).resolve().parents[2] / "ios/BioMap/BioMap/ML/Bundled"
MIN_CONF = 0.5


class Model:
    def __init__(self):
        self.interp = tf.lite.Interpreter(model_path=str(ROOT / "BundledBirdModel.tflite"), num_threads=4)
        self.interp.allocate_tensors()
        self.inp = self.interp.get_input_details()[0]["index"]
        self.out = self.interp.get_output_details()[0]["index"]
        self.labels = json.loads((ROOT / "BundledBirdLabels.json").read_text())

    def probs(self, x):
        self.interp.set_tensor(self.inp, x[None].astype(np.float32))
        self.interp.invoke()
        return self.interp.get_tensor(self.out)[0].copy()


def verdict(p, labels, truth):
    i = int(np.argmax(p))
    ok = labels[i] == truth
    conf = float(p[i])
    return ok, ok and conf >= MIN_CONF, (not ok) and conf >= MIN_CONF and labels[i] != "Unknown / Not a Bird"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--set", required=True)
    ap.add_argument("--pipelines", default=",".join(G.PIPELINES))
    ap.add_argument("--json")
    ap.add_argument("--half", choices=["all", "even", "odd"], default="all",
                    help="Evaluate only every other species (to check the gates aren't fitted to the set they were read from).")
    a = ap.parse_args()
    root = pathlib.Path(a.set)
    items = json.loads((root / "manifest.json").read_text())
    if a.half != "all":
        species = sorted({it["label"] for it in items})
        keep = {s for i, s in enumerate(species) if i % 2 == (0 if a.half == "even" else 1)}
        items = [it for it in items if it["label"] in keep]
    m = Model()
    pipes = a.pipelines.split(",")
    agg = {}
    for it in items:
        x = G.load224(root / it["file"])
        for cond in G.CONDITIONS:
            y = G.simulate(x, cond, seed=zlib.crc32(f"{it['file']}|{cond}".encode()))
            p0 = m.probs(y)
            for name in pipes:
                if name == "none":
                    modes = {"single": p0}
                else:
                    pc = m.probs(G.PIPELINES[name](y))
                    modes = {"single": pc, "tta": (p0 + pc) / 2, "w70": 0.3 * p0 + 0.7 * pc,
                             "pickmax": pc if pc.max() >= p0.max() else p0}
                for mode, p in modes.items():
                    t1, shown, wrong = verdict(p, m.labels, it["label"])
                    k = (cond, name, mode)
                    a_ = agg.setdefault(k, [0, 0, 0, 0])
                    a_[0] += t1; a_[1] += shown; a_[2] += wrong; a_[3] += 1
    res = {f"{c}|{n}|{md}": {"top1": v[0] / v[3], "shown": v[1] / v[3], "wrong": v[2] / v[3], "n": v[3]} for (c, n, md), v in agg.items()}
    for cond in G.CONDITIONS:
        print(f"\n== {cond}  (n={res[f'{cond}|none|single']['n']})")
        print(f"{'pipeline':16s}{'mode':8s}{'top1':>7s}{'shown':>8s}{'wrong':>8s}")
        base = res[f"{cond}|none|single"]
        for name in pipes:
            for mode in (["single"] if name == "none" else ["single", "tta", "w70", "pickmax"]):
                r = res[f"{cond}|{name}|{mode}"]
                d = "" if name == "none" else f"  ({r['shown'] - base['shown']:+.0%} shown)"
                print(f"{name:16s}{mode:8s}{r['top1']:7.0%}{r['shown']:8.0%}{r['wrong']:8.0%}{d}")
    if a.json:
        pathlib.Path(a.json).write_text(json.dumps(res, indent=1))


if __name__ == "__main__":
    main()
