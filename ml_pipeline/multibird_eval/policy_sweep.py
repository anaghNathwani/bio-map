"""Chooses the rule for reporting extra species from the window answers recorded by the harness (windows.json).

A species other than the primary (whole-image) one is reported when its best window is >= T, or when >= 2 windows agree on it and its
best is >= T_corr. Sweeps T / T_corr / window source and prints, per layout, how often every bird was found and how many wrong
species were reported per frame (the single and same-species controls should stay near zero).

  python policy_sweep.py --manifest M --results windows.json
"""
import argparse, json, collections


def evaluate(res, man, T, Tc, sources):
    agg = collections.defaultdict(lambda: dict(n=0, allfound=0, found=0, species=0, extras=0))
    for r in res:
        m = man[r["file"]]; truth = set(m["truth"]); primary = r.get("primary")
        best, count = {}, collections.Counter()
        for h in r["hits"]:
            if h["source"] not in sources:
                continue
            count[h["species"]] += 1
            if h["species"] not in best or best[h["species"]] < h["conf"]:
                best[h["species"]] = h["conf"]
        extra = {s for s, c in best.items() if s != primary and (c >= T or (count[s] >= 2 and c >= Tc))}
        extra = set(sorted(extra, key=lambda s: -best[s])[:3])
        found = ({primary} if primary else set()) | extra
        g = agg[m["layout"]]
        g["n"] += 1; g["species"] += len(truth); g["found"] += len(truth & found)
        g["allfound"] += truth <= found; g["extras"] += len(found - truth)
    return agg


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--manifest", required=True); ap.add_argument("--results", required=True)
    a = ap.parse_args()
    man = {m["file"]: m for m in json.load(open(a.manifest))}
    res = json.load(open(a.results))
    print(f"{'T':>4s}{'Tcorr':>6s}{'src':>7s} | " + " | ".join(f"{l:^15s}" for l in ("pair", "triple", "unequal")) + " | wrong species per frame: same single")
    print(" " * 20 + "| " + " | ".join(f"{'all found':>8s}{'recall':>7s}" for _ in range(3)))
    for src_name, sources in (("tile", {"tile"}), ("all", {"tile", "salient", "detector"})):
        for T in (0.5, 0.6, 0.7, 0.8, 0.9):
            for Tc in (0.5, 0.6, 0.7):
                if Tc > T:
                    continue
                g = evaluate(res, man, T, Tc, sources)
                cells = " | ".join(f"{100*g[l]['allfound']/g[l]['n']:7.0f}%{100*g[l]['found']/g[l]['species']:6.0f}%" for l in ("pair", "triple", "unequal"))
                print(f"{T:4.1f}{Tc:6.1f}{src_name:>7s} | {cells} | {g['same']['extras']/g['same']['n']:11.2f}{g['single']['extras']/g['single']['n']:7.2f}")


if __name__ == "__main__":
    main()
