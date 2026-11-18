"""apply_edits.py ORIGINAL.tflite OUT.tflite edits.json  -> patched copy + diff report (JSON next to OUT).
edits.json: {"ops":[
  {"op":"bias_add","tensor":1,"index":14,"delta":-1.0},
  {"op":"weight_chroma_damp","tensor":54,"channels":[14],"alpha":0.5},
  {"op":"weight_warm_project","tensor":54,"channels":[14],"alpha":1.0,"dir":[0.35,0.02,-0.5]}]}
Weights are re-snapped to the grid of the QUANTIZE op that consumes them; original is never written."""
import sys, json
import numpy as np
sys.path.insert(0, __import__("os").path.dirname(__import__("os").path.abspath(__file__)))
from tflite_edit import Model, sha

def snap(m, idx, w):
    sc, zp, qmin, qmax, lo, hi = m.quant_op_for_weight(idx)
    return (np.clip(np.round(w / sc), qmin - zp, qmax - zp) * sc).astype(np.float32)

def main(src, dst, recipe):
    ops = json.load(open(recipe))["ops"]; m = Model.load(src); before = {}; rep = []
    for o in ops:
        t = o["tensor"]; before.setdefault(t, m.get(t))
        w = m.get(t)
        if o["op"] == "bias_add":
            w[o["index"]] += o["delta"]
        elif o["op"] == "weight_chroma_damp":
            for c in o["channels"]:
                g = w[c].mean(-1, keepdims=True) * np.ones(3); w[c] = g + (1 - o["alpha"]) * (w[c] - g)
            w = snap(m, t, w)
        elif o["op"] == "weight_warm_project":
            u = np.array(o["dir"], float); u /= np.linalg.norm(u)
            for c in o["channels"]: w[c] = w[c] - o["alpha"] * (w[c] @ u)[..., None] * u
            w = snap(m, t, w)
        else: raise ValueError(o["op"])
        m.set(t, w)
    for t, b in before.items():
        a = m.get(t); ch = a != b
        rep.append(dict(tensor=t, name=m.name(t), n_changed=int(ch.sum()), n_total=int(a.size), pct=float(100 * ch.mean()), max_abs_change=float(np.abs(a - b).max())))
    m.save(dst)
    r = dict(src=src, src_sha256=sha(src), dst=dst, dst_sha256=sha(dst), tensors=rep, recipe=ops)
    json.dump(r, open(dst + ".report.json", "w"), indent=1); print(json.dumps(r, indent=1))

if __name__ == "__main__": main(*sys.argv[1:4])
