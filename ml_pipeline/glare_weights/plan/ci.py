"""Paired bootstrap (unit = photo, 90 photos x 5 conds) of candidate minus baseline. Dev split only. usage: ci.py name1 name2 ..."""
import sys; sys.path.insert(0,'.')
import numpy as np
from devlib import *
S="/private/tmp/claude-501/-Users-anagh-important-congressional/a59f9319-dd57-4a56-a8c8-2bbdac3ab64f/scratchpad/"
base=evaluate(ORIG)
def pm(a,b,c): return boot_diff(a,b,cond=c)
def glare(a,b):
    # mean over 4 glare conds, per photo
    idx=np.arange(len(a)).reshape(-1,5)[:,1:]; per=(a-b)[idx].mean(1); rng=np.random.default_rng(0)
    bs=[per[rng.integers(0,90,90)].mean() for _ in range(2000)]
    return per.mean(),np.percentile(bs,2.5),np.percentile(bs,97.5)
for nm in sys.argv[1:]:
    r=evaluate(S+"cand_"+nm+".tflite")
    for mode in ("raw","w70"):
        # reference: raw -> unedited raw; w70 -> unedited w70 (edit combined with correction vs correction alone)
        o=[]
        for k in ("top1","shown","wrong","margin"):
            g=glare(r[mode][k],base[mode][k]); c=pm(r[mode][k],base[mode][k],0)
            o.append(f"{k}: glare {g[0]*100 if k!='margin' else g[0]:+.2f} [{g[1]*100 if k!='margin' else g[1]:+.2f},{g[2]*100 if k!='margin' else g[2]:+.2f}] clean {c[0]*100 if k!='margin' else c[0]:+.2f} [{c[1]*100 if k!='margin' else c[1]:+.2f},{c[2]*100 if k!='margin' else c[2]:+.2f}]")
        imp=sum(pm(r[mode]['shown'],base[mode]['shown'],c)[0]>0 for c in range(1,5))
        print(f"## {nm} [{mode} vs unedited {mode}] (pts, 95% CI)  shown-improved conds {imp}/4"); print("   "+"\n   ".join(o),flush=True)
# also: edit-alone(raw) vs the app correction alone (w70 unedited)
