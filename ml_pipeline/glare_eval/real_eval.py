"""Measures the photo classifier on REAL low-sun photos versus real daylight photos of the same species.

  python real_eval.py --set /path/to/real_lowsun [--json out.json]

Systems: the unedited model; the model with the app's glare correction (adaptive gating + 30/70 blend, as BirdClassifier does).
Metrics per bucket (low / day): top1, shown-right (right AND confidence >= 0.5), wrong-shown (confidently wrong, not background),
and how often the app's correction fires. Differences use a paired bootstrap over photos.
"""
import argparse, json, pathlib
import numpy as np
import glare_lib as G
from eval import Model, MIN_CONF


def bootstrap_ci(diff, n=2000, seed=0):
    rng = np.random.default_rng(seed)
    d = np.asarray(diff, float)
    means = [d[rng.integers(0, len(d), len(d))].mean() for _ in range(n)]
    return float(np.percentile(means, 2.5)), float(np.percentile(means, 97.5))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--set", required=True)
    ap.add_argument("--json")
    a = ap.parse_args()
    root = pathlib.Path(a.set)
    items = json.loads((root / "manifest.json").read_text())
    m = Model()
    rows = []
    for it in items:
        x = G.load224(root / it["file"])
        p0 = m.probs(x)
        fixed, flags = G.adaptive(x, return_flags=True)
        p1 = (0.3 * p0 + 0.7 * m.probs(fixed)) if flags else p0
        r = {"file": it["file"], "kind": it["kind"], "label": it["label"], "elev": it["sun_elevation"], "fired": bool(flags)}
        for tag, p in (("raw", p0), ("fix", p1)):
            i = int(np.argmax(p)); ok = m.labels[i] == it["label"]; conf = float(p[i])
            r[f"{tag}_top1"] = ok
            r[f"{tag}_shown"] = ok and conf >= MIN_CONF
            r[f"{tag}_wrong"] = (not ok) and conf >= MIN_CONF and m.labels[i] != "Unknown / Not a Bird"
        rows.append(r)
    res = {}
    for kind in ("low", "day"):
        sub = [r for r in rows if r["kind"] == kind]
        if not sub:
            continue
        res[kind] = {"n": len(sub), "fired": float(np.mean([r["fired"] for r in sub]))}
        for tag in ("raw", "fix"):
            for k in ("top1", "shown", "wrong"):
                res[kind][f"{tag}_{k}"] = float(np.mean([r[f"{tag}_{k}"] for r in sub]))
        for k in ("top1", "shown", "wrong"):
            d = [float(r[f"fix_{k}"]) - float(r[f"raw_{k}"]) for r in sub]
            res[kind][f"fix_minus_raw_{k}"] = (float(np.mean(d)), *bootstrap_ci(d))
    # the real gap: low-sun vs daylight, per species (unpaired across photos; report species-matched means)
    sp = sorted({r["label"] for r in rows})
    both = [s for s in sp if any(r["label"] == s and r["kind"] == "low" for r in rows) and any(r["label"] == s and r["kind"] == "day" for r in rows)]
    res["species_with_both"] = len(both)
    for k in ("top1", "shown"):
        d = [np.mean([r[f"raw_{k}"] for r in rows if r["label"] == s and r["kind"] == "low"]) -
             np.mean([r[f"raw_{k}"] for r in rows if r["label"] == s and r["kind"] == "day"]) for s in both]
        res[f"gap_low_minus_day_{k}"] = (float(np.mean(d)), *bootstrap_ci(d))
    print(json.dumps(res, indent=1))
    if a.json:
        pathlib.Path(a.json).write_text(json.dumps({"summary": res, "rows": rows}, indent=1))


if __name__ == "__main__":
    main()
