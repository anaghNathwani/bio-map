"""Does rejecting an 'extra' species whose best window mostly overlaps the window already explained by the primary species cut the
wrong extras on single-bird frames without losing real second birds?  (box = x, y, w, h, normalised)"""
import argparse, json, collections


def frac_inside(a, b):
    """Share of window a's area that lies inside window b."""
    ax, ay, aw, ah = a; bx, by, bw, bh = b
    ix = max(0, min(ax + aw, bx + bw) - max(ax, bx)); iy = max(0, min(ay + ah, by + bh) - max(ay, by))
    return ix * iy / (aw * ah)


def evaluate(res, man, T, Tc, tau):
    agg = collections.defaultdict(lambda: dict(n=0, allfound=0, found=0, species=0, extras=0))
    for r in res:
        m = man[r["file"]]; truth = set(m["truth"]); primary = r.get("primary")
        best, count = {}, collections.Counter()
        for h in r["hits"]:
            count[h["species"]] += 1
            if h["species"] not in best or best[h["species"]]["conf"] < h["conf"]:
                best[h["species"]] = h
        ref = best.get(primary)
        extra = set()
        for s, h in sorted(best.items(), key=lambda kv: -kv[1]["conf"]):
            if s == primary or not (h["conf"] >= T or (count[s] >= 2 and h["conf"] >= Tc)):
                continue
            if tau is not None and ref is not None and frac_inside(h["box"], ref["box"]) > tau:
                continue                      # that region is already explained by the primary species
            extra.add(s)
        extra = set(sorted(extra, key=lambda s: -best[s]["conf"])[:3])
        found = ({primary} if primary else set()) | extra
        g = agg[m["layout"]]
        g["n"] += 1; g["species"] += len(truth); g["found"] += len(truth & found)
        g["allfound"] += truth <= found; g["extras"] += len(found - truth)
    return agg


def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--manifest", required=True); ap.add_argument("--results", required=True)
    a = ap.parse_args()
    man = {m["file"]: m for m in json.load(open(a.manifest))}; res = json.load(open(a.results))
    print(f"{'T':>4s}{'Tc':>5s}{'tau':>6s} | {'pair':>8s}{'triple':>8s}{'unequal':>9s} (all found) | wrong species per frame: same single | pair/triple/unequal")
    for T, Tc in ((0.5, 0.5), (0.6, 0.5), (0.7, 0.5), (0.8, 0.5)):
        for tau in (None, 0.7, 0.5, 0.3):
            g = evaluate(res, man, T, Tc, tau)
            af = lambda l: f"{100*g[l]['allfound']/g[l]['n']:5.0f}%"
            ex = lambda l: f"{g[l]['extras']/g[l]['n']:.2f}"
            print(f"{T:4.1f}{Tc:5.1f}{str(tau):>6s} | {af('pair'):>8s}{af('triple'):>8s}{af('unequal'):>9s}             | {ex('same'):>26s}{ex('single'):>7s} | {ex('pair')}/{ex('triple')}/{ex('unequal')}")


if __name__ == "__main__":
    main()
