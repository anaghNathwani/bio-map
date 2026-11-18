"""DEV-split sanity check (reproduces Stage 2's numbers for chroma damp ch14 alpha 0.5). usage: run_dev.py SETDIR"""
import sys, json
import numpy as np
from evallib import *
from analysis import *
setdir = sys.argv[1]
items = split_items(setdir, "dev"); inp = build_inputs(setdir, items)
print("dev species:", len({i['label'] for i in items}), "photos:", len(items))
res, info = evaluate_all(inp)
tab = table(res, inp); C, verdict, da, dc = budget(res, info, inp)
print_tables(tab, da, dc, len(items))
for c in C: print(("PASS " if c["ok"] else "FAIL ") + c["name"] + " -> " + c["detail"])
print("dev verdict (informational):", verdict)
write_csv(HERE + "/dev_per_photo_results.csv", res, inp, items)
