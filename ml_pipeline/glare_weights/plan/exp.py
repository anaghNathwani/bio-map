"""Experiment runner. Every evaluated configuration is appended to configs_log.jsonl (selection-effect accounting)."""
import sys, time, json; sys.path.insert(0,'.')
import numpy as np
from tflite_edit import *
from devlib import *
OUT="/private/tmp/claude-501/-Users-anagh-important-congressional/a59f9319-dd57-4a56-a8c8-2bbdac3ab64f/scratchpad/"
LOG="configs_log.jsonl"

def table(res, tag):
    d=load_cache(); rows={}
    for mode in ("raw","w70"):
        for c,cn in enumerate(CONDS):
            rows[(mode,cn)]=summarize(res,mode,c)
    return rows

def fmt(rows, mode):
    s=[]
    for cn in CONDS:
        r=rows[(mode,cn)]
        s.append(f"{cn[:4]} t{r['top1']*100:3.0f} s{r['shown']*100:3.0f} w{r['wrong']*100:3.0f} m{r['margin']:+.2f}")
    return " | ".join(s)

def glare_mean(rows, mode, k):
    return np.mean([rows[(mode,c)][k] for c in CONDS[1:]])

def run(name, editfn, log=True):
    path=OUT+"cand_"+name.replace(" ","_").replace("/","_")+".tflite"
    m=Model.load(ORIG); info=editfn(m) or {}; m.save(path)
    res=evaluate(path); rows=table(res,name)
    print(f"[{name}] finite={res['finite']}")
    for mode in ("raw","w70"): print("  ",mode, fmt(rows,mode), f"|| glare-mean s{glare_mean(rows,mode,'shown')*100:.1f} w{glare_mean(rows,mode,'wrong')*100:.1f}")
    if log:
        open(LOG,"a").write(json.dumps(dict(name=name,info=info,glare_shown_raw=glare_mean(rows,"raw","shown"),clean_shown_raw=rows[("raw","clean")]["shown"]))+"\n")
    return res, rows

if __name__=="__main__":
    t=time.time()
    res,rows=run("baseline", lambda m: None, log=False)
    print("time",time.time()-t)
    import pickle; pickle.dump(res,open(OUT+"res_baseline.pkl","wb"))
