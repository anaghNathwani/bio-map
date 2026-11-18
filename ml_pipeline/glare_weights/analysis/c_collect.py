"""usage: c_collect.py GLARE_SET_DIR  -> dev-split only. saves collect.npz/pkl"""
import sys,json,zlib,pickle,numpy as np,tensorflow as tf
sys.path.insert(0,"/Users/anagh/important/congressional/birdmap/ml_pipeline/glare_eval")
import glare_lib as G
root=sys.argv[1]; R="/Users/anagh/important/congressional/birdmap/ios/BioMap/BioMap/ML/Bundled/"
items=json.load(open(root+"/manifest.json")); sp=sorted({i['label'] for i in items})
dev={s for k,s in enumerate(sp) if k%2==0}; items=[i for i in items if i['label'] in dev]
print("dev species",len(dev),"images",len(items))
labels=json.load(open(R+"BundledBirdLabels.json")); L={l:i for i,l in enumerate(labels)}
it=tf.lite.Interpreter(model_path=R+"BundledBirdModel.tflite",experimental_preserve_all_tensors=True); it.allocate_tensors()
d=it.get_tensor_details(); ops=it._get_ops_details()
# layers: float outputs of CONV/DW/ADD/AVGPOOL/FC ; range from following QUANTIZE out
layers=[]
for k,o in enumerate(ops):
    if o['op_name'] in('CONV_2D','DEPTHWISE_CONV_2D','ADD','AVERAGE_POOL_2D'):
        t=o['outputs'][0]; hi=None
        if k+1<len(ops) and ops[k+1]['op_name']=='QUANTIZE':
            q=d[ops[k+1]['outputs'][0]]['quantization']; hi=q[0]*(255-q[1]); lo=q[0]*(0-q[1])
        layers.append((k,o['op_name'],t,lo if hi else None,hi))
print(len(layers),"layers; ranges sample",[(l[1],l[3],l[4]) for l in layers[:4]],[(l[1],l[3],l[4]) for l in layers[-4:]])
inp=it.get_input_details()[0]['index']; out=it.get_output_details()[0]['index']
pool=[l for l in layers if l[1]=='AVERAGE_POOL_2D'][0][2]
res={c:{} for c in G.CONDITIONS}
meta=[]
for n,im in enumerate(items):
    x=G.load224(root+"/"+im['file']); meta.append((im['file'],im['label']))
    for c in G.CONDITIONS:
        y=G.simulate(x,c,zlib.crc32(f"{im['file']}|{c}".encode()))
        it.set_tensor(inp,y[None].astype(np.float32)); it.invoke()
        r={}
        for k,nm,t,lo,hi in layers:
            a=it.get_tensor(t)[0]
            if a.ndim==3:
                m=a.mean((0,1)); sat=(a>=hi-1e-3).mean((0,1)) if hi else np.zeros(a.shape[-1]); z=(a<=1e-6).mean((0,1))
            else: m=a.reshape(-1); sat=np.zeros_like(m); z=(m<=1e-6)*1.0
            r[k]=(m.astype(np.float32),sat.astype(np.float32),z.astype(np.float32))
        r['logit']=None
        res[c].setdefault('layers',[]).append(r)
        res[c].setdefault('pool',[]).append(it.get_tensor(pool).reshape(-1).copy())
        res[c].setdefault('prob',[]).append(it.get_tensor(out)[0].copy())
pickle.dump(dict(res=res,meta=meta,layers=[(l[0],l[1],l[3],l[4]) for l in layers],lab=L),open("collect.pkl","wb"))
