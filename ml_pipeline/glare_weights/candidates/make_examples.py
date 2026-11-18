"""Contact sheet of 8 test-split photos under simulated glare. Selection rule fixed in advance of looking at predictions:
every 4th test species (alphabetical, starting with the first), its first photo in the manifest, conditions cycling
golden, veil, backlit, silhouette. Predictions come from test_per_photo_results.csv (no model is run here).
usage: make_examples.py SETDIR"""
import sys, csv, json, zlib, os
import matplotlib; matplotlib.use("Agg")
import matplotlib.pyplot as plt
from evallib import *
setdir = sys.argv[1]
items = split_items(setdir, "test")
rows = {}
for r in csv.DictReader(open(HERE + "/test_per_photo_results.csv")):
    rows[(r["photo_file"], r["condition"], r["system"])] = r
species = sorted({i["label"] for i in items})[::4]
chosen = []
for k, s in enumerate(species):
    it = next(i for i in items if i["label"] == s); chosen.append((it, ["golden", "veil", "backlit", "silhouette"][k % 4]))
fig, axs = plt.subplots(2, 4, figsize=(16, 10.5))
for ax, (it, cond) in zip(axs.ravel(), chosen):
    x = G.load224(os.path.join(setdir, it["file"])); y = G.simulate(x, cond, zlib.crc32(f"{it['file']}|{cond}".encode()))
    ax.imshow(y); ax.axis("off")
    ax.set_title(f"True: {it['label']}\n({cond} glare)", fontsize=11)
    lines = []
    for nm, sy in (("Unedited", "unedited"), ("Candidate", "candidate")):
        r = rows[(it["file"], cond, sy)]; ok = r["top1"] == "1"
        lines.append((f"{nm}: {r['top_label'][:26]} {float(r['confidence']):.2f}  [{'RIGHT' if ok else 'wrong'}]", "#1a7f37" if ok else "#c62828"))
    for j, (t, c) in enumerate(lines):
        ax.text(0.5, -0.04 - 0.09 * j, t, transform=ax.transAxes, ha="center", va="top", fontsize=9.5, color=c)
fig.suptitle("Test-split photos under simulated glare: unedited model vs chroma-damped candidate (no app pre-correction; confidence shown)", fontsize=12)
plt.subplots_adjust(left=0.01, right=0.99, top=0.88, bottom=0.09, hspace=0.5, wspace=0.08); plt.savefig(HERE + "/examples.png", dpi=110)
json.dump([dict(file=i["file"], label=i["label"], condition=c, source=i["source"], license=i["license"]) for i, c in chosen], open(HERE + "/examples_attribution.json", "w"), indent=1)
for i, c in chosen: print(i["file"], c, i["source"], i["license"])
