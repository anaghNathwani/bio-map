"""Scores the app's multi-bird step on the frames from make_set.py.

  python score.py --manifest DIR/manifest.json --results results.json

For each frame the app reports a primary species (whole-image classification) plus 'additional' species (the multi-bird step).
A bird counts as FOUND when its species appears in either. Reported per layout:
  all found     every species in the frame was found
  recall        share of the frame's species that were found
  false extras  species reported that are NOT in the frame, per frame (the controls should be near zero)
"""
import argparse, json, collections


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--manifest", required=True)
    ap.add_argument("--results", required=True)
    a = ap.parse_args()
    man = {m["file"]: m for m in json.load(open(a.manifest))}
    res = {r["file"]: r for r in json.load(open(a.results))}
    agg = collections.defaultdict(lambda: dict(n=0, allfound=0, found=0, species=0, extras=0, nothing=0, secs=0.0))
    for f, r in res.items():
        m = man[f]
        truth = set(m["truth"])
        found = ({r["primary"]} if r.get("primary") else set()) | {x["species"] for x in r.get("additional", [])}
        g = agg[m["layout"]]
        g["n"] += 1; g["species"] += len(truth); g["found"] += len(truth & found)
        g["allfound"] += truth <= found; g["extras"] += len(found - truth); g["nothing"] += (not found); g["secs"] += r.get("sec", 0)
    print(f"{'layout':9s}{'frames':>7s}{'all found':>11s}{'recall':>9s}{'extras/frame':>14s}{'no answer':>11s}{'sec/frame':>11s}")
    for layout in ("pair", "triple", "unequal", "same", "single"):
        g = agg.get(layout)
        if not g:
            continue
        print(f"{layout:9s}{g['n']:7d}{100*g['allfound']/g['n']:10.0f}%{100*g['found']/g['species']:8.0f}%{g['extras']/g['n']:14.2f}{100*g['nothing']/g['n']:10.0f}%{g['secs']/g['n']:11.2f}")


if __name__ == "__main__":
    main()
