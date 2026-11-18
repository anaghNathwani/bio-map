"""TEST-split evaluation of the pre-registered candidate (chroma damp ch14, alpha 0.5). Meant to be run ONCE.
usage: run_test.py SETDIR --run-once            (refuses if test_run_log.jsonl already has a run)
       run_test.py SETDIR --rerun "reason"       (only for a genuine bug fix; logged)"""
import sys, json, time, hashlib, os
import numpy as np
from evallib import *
from analysis import *
setdir = sys.argv[1]; flag = sys.argv[2] if len(sys.argv) > 2 else ""
LOG = HERE + "/test_run_log.jsonl"
prev = [json.loads(l) for l in open(LOG)] if os.path.exists(LOG) else []
if flag == "--run-once" and prev: sys.exit("test already run; see test_run_log.jsonl")
if flag not in ("--run-once", "--rerun"): sys.exit("need --run-once or --rerun REASON")
reason = "first and only run" if flag == "--run-once" else sys.argv[3]
sha = lambda p: hashlib.sha256(open(p, "rb").read()).hexdigest()
items = split_items(setdir, "test"); inp = build_inputs(setdir, items)
res, info = evaluate_all(inp)
tab = table(res, inp); C, verdict, da, dc = budget(res, info, inp)
print_tables(tab, da, dc, len(items))
for c in C: print(("PASS " if c["ok"] else "FAIL ") + c["name"] + " -> " + c["detail"])
print("TEST VERDICT:", verdict)
# red/orange subset (decided from manifest labels): those of the four that fall in the odd (test) half
RED = ["Northern Cardinal", "Vermilion Flycatcher", "Scarlet Tanager", "Baltimore Oriole"]
present = [s for s in RED if any(i["label"] == s for i in items)]
red = {}
for s in present:
    rows = [r for r in range(len(inp["truth"])) if inp["cond"][r] == 0 and items[inp["photo"][r]]["label"] == s]
    red[s] = dict(n=len(rows), **{sy: dict(top1=int(res[sy]["top1"][rows].sum()), shown=int(res[sy]["shown"][rows].sum()), wrong=int(res[sy]["wrong"][rows].sum()))
                                  for sy in SYSTEMS})
allrows = [r for r in range(len(inp["truth"])) if inp["cond"][r] == 0 and items[inp["photo"][r]]["label"] in present]
red["ALL"] = dict(n=len(allrows), **{sy: dict(top1=int(res[sy]["top1"][allrows].sum()), shown=int(res[sy]["shown"][allrows].sum()), wrong=int(res[sy]["wrong"][allrows].sum())) for sy in SYSTEMS})
print("red/orange clean subset (counts):", json.dumps(red, indent=1))
write_csv(HERE + "/test_per_photo_results.csv", res, inp, items)
js = dict(n_photos=len(items), n_species=len({i["label"] for i in items}), table=tab, d_candidate_vs_unedited=da, d_candcorr_vs_corr=dc,
          criteria=C, verdict=verdict, red_orange=red, sanity=info)
json.dump(js, open(HERE + "/test_results.json", "w"), indent=1)
open(LOG, "a").write(json.dumps(dict(time=time.strftime("%Y-%m-%d %H:%M:%S"), reason=reason, candidate_sha256=sha(CAND), original_sha256=sha(ORIG), verdict=verdict)) + "\n")
