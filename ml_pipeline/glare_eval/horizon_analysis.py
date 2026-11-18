"""Real low-sun analysis: how big is the gap, what explains it, and does any simple pre-correction help?

Combines the real photo sets (daylight control, golden hour, and near-horizon) and reports, with species-split development / test
halves (even / odd species) and bootstrap intervals:
  1. accuracy by sun elevation;
  2. which simple photo measurements (brightness, sharpness, contrast, saturation, warmth ...) go with errors;
  3. whether candidate pre-corrections (blended 30/70 into the model's probabilities, like the app does) help near-horizon photos.

  python horizon_analysis.py --sets DIR [DIR ...] --json out.json
"""
import argparse, json, pathlib
import numpy as np
import glare_lib as G
from eval import Model, MIN_CONF


def laplacian_var(y):
    k = y[1:-1, 1:-1] * 4 - y[:-2, 1:-1] - y[2:, 1:-1] - y[1:-1, :-2] - y[1:-1, 2:]
    return float(k.var())


def extra_stats(x):
    y = G.lum(x)
    mx, mn = x.max(2), x.min(2)
    return {"mean_lum": float(y.mean()), "dark_frac": float((y < 0.15).mean()), "contrast_std": float(y.std()),
            "sharpness": laplacian_var(y), "saturation": float(np.mean((mx - mn) / np.maximum(mx, 1e-4))), **G.stats(x)}


def gamma_lift(x, target=0.45):
    y = float(G.lum(x).mean())
    if y >= 0.40:
        return x
    g = np.clip(np.log(target) / np.log(max(y, 0.03)), 0.5, 1.0)
    return np.clip(np.power(np.maximum(x, 1e-4), g), 0, 1)


CANDIDATES = {
    "app_adaptive": lambda x: G.adaptive(x),
    "shadow_lift": G.shadow_lift,
    "auto_levels": G.auto_levels,
    "gamma_lift": gamma_lift,
    "gray_world": G.gray_world,
}


def boot(vals, n=2000, seed=0):
    v = np.asarray(vals, float)
    if len(v) == 0:
        return (float("nan"),) * 3
    rng = np.random.default_rng(seed)
    m = [v[rng.integers(0, len(v), len(v))].mean() for _ in range(n)]
    return float(v.mean()), float(np.percentile(m, 2.5)), float(np.percentile(m, 97.5))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sets", nargs="+", required=True)
    ap.add_argument("--json")
    a = ap.parse_args()
    m = Model()
    rows = []
    for d in a.sets:
        d = pathlib.Path(d)
        for it in json.loads((d / "manifest.json").read_text()):
            x = G.load224(d / it["file"])
            p0 = m.probs(x)
            r = {"file": it["file"], "label": it["label"], "elev": it["sun_elevation"], **extra_stats(x)}
            i = int(np.argmax(p0)); ok = m.labels[i] == it["label"]
            r.update(raw_top1=bool(ok), raw_shown=bool(ok and p0[i] >= MIN_CONF), raw_conf=float(p0[i]),
                     raw_wrong=bool((not ok) and p0[i] >= MIN_CONF and m.labels[i] != "Unknown / Not a Bird"))
            for name, fn in CANDIDATES.items():
                y = fn(x)
                changed = not np.array_equal(y, x)
                p = (0.3 * p0 + 0.7 * m.probs(y)) if changed else p0
                j = int(np.argmax(p)); okc = m.labels[j] == it["label"]
                r[f"{name}_shown"] = bool(okc and p[j] >= MIN_CONF); r[f"{name}_top1"] = bool(okc)
                r[f"{name}_wrong"] = bool((not okc) and p[j] >= MIN_CONF and m.labels[j] != "Unknown / Not a Bird")
                r[f"{name}_changed"] = changed
            rows.append(r)
    species = sorted({r["label"] for r in rows})
    half = {s: ("dev" if i % 2 == 0 else "test") for i, s in enumerate(species)}
    for r in rows:
        r["half"] = half[r["label"]]
        r["bucket"] = "day" if r["elev"] >= 35 else ("horizon" if r["elev"] < 3 else "golden")
    out = {"n": len(rows), "buckets": {}, "corr": {}, "cands": {}}

    print("== 1. accuracy by sun elevation (raw model)")
    print(f"{'bucket':9s}{'n':>5s}{'top1':>8s}{'shown':>8s}{'wrong':>8s}")
    for b in ("day", "golden", "horizon"):
        sub = [r for r in rows if r["bucket"] == b]
        t, s, w = (boot([r[f"raw_{k}"] for r in sub]) for k in ("top1", "shown", "wrong"))
        out["buckets"][b] = {"n": len(sub), "top1": t, "shown": s, "wrong": w}
        print(f"{b:9s}{len(sub):5d}{100*t[0]:6.1f}% {100*s[0]:6.1f}% {100*w[0]:6.1f}%   (top1 95% CI {100*t[1]:.1f}-{100*t[2]:.1f})")
    # gap near horizon vs day on shared species
    both = [s for s in species if any(r["label"] == s and r["bucket"] == "horizon" for r in rows) and any(r["label"] == s and r["bucket"] == "day" for r in rows)]
    for k in ("top1", "shown"):
        d = [np.mean([r[f"raw_{k}"] for r in rows if r["label"] == s and r["bucket"] == "horizon"]) - np.mean([r[f"raw_{k}"] for r in rows if r["label"] == s and r["bucket"] == "day"]) for s in both]
        g = boot(d); out[f"gap_horizon_minus_day_{k}"] = g
        print(f"species-matched gap, horizon minus day, {k}: {100*g[0]:+.1f} points [{100*g[1]:+.1f}, {100*g[2]:+.1f}] over {len(both)} species")

    print("\n== 2. what goes with errors among near-horizon photos (correlation with 'top-1 right'; n=%d)" % sum(1 for r in rows if r["bucket"] == "horizon"))
    hz = [r for r in rows if r["bucket"] == "horizon"]; dy = [r for r in rows if r["bucket"] == "day"]
    ok = np.array([r["raw_top1"] for r in hz], float)
    print(f"{'measurement':14s}{'corr w/ right':>14s}{'horizon median':>16s}{'day median':>12s}")
    for k in ("mean_lum", "dark_frac", "contrast_std", "sharpness", "saturation", "border_warmth", "range", "backlight", "clipped", "dark_channel"):
        v = np.array([r[k] for r in hz])
        c = float(np.corrcoef(v, ok)[0, 1]) if v.std() > 0 and ok.std() > 0 else float("nan")
        out["corr"][k] = {"corr": c, "horizon_median": float(np.median(v)), "day_median": float(np.median([r[k] for r in dy]))}
        print(f"{k:14s}{c:14.2f}{np.median(v):16.3f}{np.median([r[k] for r in dy]):12.3f}")

    print("\n== 3. pre-corrections blended 30/70 (like the app) on near-horizon photos: change in 'right answer shown', points")
    print(f"{'candidate':14s}{'half':>6s}{'n':>5s}{'changed':>9s}{'shown':>16s}{'wrong':>16s}")
    for name in CANDIDATES:
        for h in ("dev", "test", "both"):
            sub = [r for r in hz if h == "both" or r["half"] == h]
            ds = boot([float(r[f"{name}_shown"]) - float(r["raw_shown"]) for r in sub])
            dw = boot([float(r[f"{name}_wrong"]) - float(r["raw_wrong"]) for r in sub])
            ch = np.mean([r[f"{name}_changed"] for r in sub])
            out["cands"][f"{name}|{h}"] = {"n": len(sub), "changed": float(ch), "shown": ds, "wrong": dw}
            print(f"{name:14s}{h:>6s}{len(sub):5d}{100*ch:8.0f}%  {100*ds[0]:+5.1f} [{100*ds[1]:+.1f},{100*ds[2]:+.1f}]  {100*dw[0]:+5.1f} [{100*dw[1]:+.1f},{100*dw[2]:+.1f}]")
        # and the cost on daylight photos
        ddy = boot([float(r[f"{name}_shown"]) - float(r["raw_shown"]) for r in dy])
        print(f"{'':14s}{'(day)':>6s}{len(dy):5d}{100*np.mean([r[f'{name}_changed'] for r in dy]):8.0f}%  {100*ddy[0]:+5.1f} [{100*ddy[1]:+.1f},{100*ddy[2]:+.1f}]")
    if a.json:
        pathlib.Path(a.json).write_text(json.dumps({"summary": out, "rows": rows}, indent=1))


if __name__ == "__main__":
    main()
