"""Summaries, paired-bootstrap intervals and the safety-budget verdict (criteria pre-agreed in plan/PLAN.md section D)."""
import numpy as np, csv
from evallib import *

KEYS = ["top1", "shown", "wrong", "margin"]
def pts(k): return 1.0 if k == "margin" else 100.0

def table(res, inp):
    """{system: {cond: {metric: mean}}}"""
    return {s: {CONDS[c]: {k: mean_cond(res[s][k], inp, c) for k in KEYS} for c in range(5)} for s in SYSTEMS}

def diffs(res, inp, a, b):
    """{cond or 'glare': {metric: (mean, lo, hi)}} of system a minus system b (paired bootstrap over photos)."""
    out = {}
    for name, conds in [(CONDS[c], [c]) for c in range(5)] + [("glare", [1, 2, 3, 4])]:
        out[name] = {k: boot(res[a][k] - res[b][k], inp, conds) for k in KEYS}
    return out

def glare_mean(tab, s, k): return float(np.mean([tab[s][c][k] for c in CONDS[1:]]))

def budget(res, info, inp):
    d_alone = diffs(res, inp, "candidate", "unedited")
    d_corr = diffs(res, inp, "candidate+corr", "unedited+corr")
    C = []
    def add(name, ok, detail): C.append(dict(name=name, ok=bool(ok), detail=detail))
    t = d_alone["clean"]["top1"]; s = d_alone["clean"]["shown"]; w = d_alone["clean"]["wrong"]
    add("1 clean top1 fall <= 2 pts and CI lower bound > -5", t[0]*100 >= -2 and t[1]*100 > -5, f"{t[0]*100:+.1f} [{t[1]*100:+.1f}, {t[2]*100:+.1f}]")
    add("2 clean shown-right fall <= 2 pts and CI lower bound > -5", s[0]*100 >= -2 and s[1]*100 > -5, f"{s[0]*100:+.1f} [{s[1]*100:+.1f}, {s[2]*100:+.1f}]")
    add("3 clean wrong-shown does not rise", w[0] <= 1e-12, f"{w[0]*100:+.1f} [{w[1]*100:+.1f}, {w[2]*100:+.1f}]")
    imp = [d_alone[c]["shown"][0] > 1e-12 for c in CONDS[1:]]; g = d_alone["glare"]["shown"]
    add("4 glare shown-right improves in >= 3 of 4 conditions and glare-mean CI lower bound > 0", sum(imp) >= 3 and g[1] > 0,
        f"{sum(imp)}/4 improved; glare mean {g[0]*100:+.1f} [{g[1]*100:+.1f}, {g[2]*100:+.1f}]")
    gs = d_corr["glare"]["shown"]; gw = d_corr["glare"]["wrong"]; cw = d_corr["clean"]["wrong"]
    add("5 candidate+correction not worse than correction alone (glare-mean shown CI lower bound >= -1 pt; wrong-shown not higher in glare mean or clean)",
        gs[1]*100 >= -1 and gw[0] <= 1e-12 and cw[0] <= 1e-12,
        f"shown glare {gs[0]*100:+.1f} [{gs[1]*100:+.1f}, {gs[2]*100:+.1f}]; wrong glare {gw[0]*100:+.1f} [{gw[1]*100:+.1f}, {gw[2]*100:+.1f}]; wrong clean {cw[0]*100:+.1f}")
    add("6 outputs finite and softmax sums to 1 (max error < 1e-3)", all(v["finite"] and v["max_psum_err"] < 1e-3 for v in info.values()),
        "; ".join(f"{k}: finite={v['finite']}, max|sum-1|={v['max_psum_err']:.1e}" for k, v in info.items()))
    # Verdict rule (fixed before the test run): FAIL = a safety criterion (1,2,3,5,6) broken with its whole interval on the harmful side,
    # or the glare-mean shown interval entirely below zero. PASS = all criteria hold. Otherwise NULL.
    harmful = (t[2] < 0 and t[0]*100 < -2) or (s[2] < 0 and s[0]*100 < -2) or g[2] < 0 or gs[2] < 0 or (w[1] > 0) or (gw[1] > 0 and gs[0] < 0) \
        or not C[5]["ok"]
    verdict = "PASS" if all(c["ok"] for c in C) else ("FAIL" if harmful else "NULL")
    return C, verdict, d_alone, d_corr

def write_csv(path, res, inp, items):
    with open(path, "w", newline="") as f:
        w = csv.writer(f); w.writerow(["photo_file", "species", "condition", "system", "top1", "shown_right", "wrong_shown", "margin", "top_label", "confidence"])
        for s in SYSTEMS:
            r = res[s]
            for i in range(len(inp["truth"])):
                it = items[inp["photo"][i]]
                w.writerow([it["file"], it["label"], CONDS[inp["cond"][i]], s, int(r["top1"][i]), int(r["shown"][i]), int(r["wrong"][i]),
                            f"{r['margin'][i]:.4f}", LABELS[r["top"][i]], f"{r['conf'][i]:.4f}"])

def print_tables(tab, d_alone, d_corr, n):
    print(f"n photos = {n}; values in % (margin in logits)")
    for k in KEYS:
        print(f"\n== {k}")
        print("%-16s" % "system" + "".join("%12s" % c for c in CONDS) + "   glare-mean")
        for s in SYSTEMS:
            print("%-16s" % s + "".join("%12.1f" % (tab[s][c][k]*pts(k)) for c in CONDS) + "%12.1f" % (glare_mean(tab, s, k)*pts(k)))
        for nm, d in (("cand - unedited", d_alone), ("cand+corr - corr", d_corr)):
            print("%-16s" % nm + "".join("%12s" % (f"{d[c][k][0]*pts(k):+.1f}[{d[c][k][1]*pts(k):+.1f},{d[c][k][2]*pts(k):+.1f}]") for c in CONDS)
                  + "  " + f"{d['glare'][k][0]*pts(k):+.1f}[{d['glare'][k][1]*pts(k):+.1f},{d['glare'][k][2]*pts(k):+.1f}]")
