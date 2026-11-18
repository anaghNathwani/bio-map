"""usage: f_stem_test.py GLARE_SET -- hypothesis test: in-memory stem-bias shift on ch14 (red-minus-blue), dev images only."""
import sys,json,zlib,numpy as np,tensorflow as tf
sys.path.insert(0,"/Users/anagh/important/congressional/birdmap/ml_pipeline/glare_eval")
import glare_lib as G
root=sys.argv[1];R="/Users/anagh/important/congressional/birdmap/ios/BioMap/BioMap/ML/Bundled/"
items=json.load(open(root+"/manifest.json"));sp=sorted({i['label'] for i in items});dev={s for k,s in enumerate(sp) if k%2==0}
items=[i for i in items if i['label'] in dev];labels=json.load(open(R+"BundledBirdLabels.json"))
it=tf.lite.Interpreter(model_path=R+"BundledBirdModel.tflite");it.allocate_tensors()
inp=it.get_input_details()[0]['index'];out=it.get_output_details()[0]['index']
imgs=[(G.load224(root+"/"+i['file']),i) for i in items]
b0=it.get_tensor(1).copy()
try:
    it.set_tensor(1,b0*1.0)
except Exception as e: print("cannot set const tensor:",e);sys.exit()
def run(delta):
    b=b0.copy()
    for ch,v in delta.items(): b[ch]+=v
    it.set_tensor(1,b)
    r={}
    for c in G.CONDITIONS:
        ok=sh=0
        for x,i in imgs:
            y=G.simulate(x,c,zlib.crc32(f"{i['file']}|{c}".encode()))
            it.set_tensor(inp,y[None].astype(np.float32));it.invoke();p=it.get_tensor(out)[0]
            t=labels[int(p.argmax())]==i['label'];ok+=t;sh+=t and p.max()>=.5
        r[c]=(ok/len(imgs),sh/len(imgs))
    return r
for name,d in [("none",{}),("ch14 bias -0.5",{14:-.5}),("ch14 bias -1.0",{14:-1.0}),("ch14 -1, ch21 +0.5",{14:-1.,21:.5})]:
    print(name,{c:"top1 %.2f shown %.2f"%v for c,v in run(d).items()})
