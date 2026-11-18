"""Part A proofs. dev images only."""
import sys; sys.path.insert(0,'.')
import numpy as np, tensorflow as tf
from tflite_edit import *
from devlib import *
OUT="/private/tmp/claude-501/-Users-anagh-important-congressional/a59f9319-dd57-4a56-a8c8-2bbdac3ab64f/scratchpad/"
m=Model.load(ORIG); m.save(OUT+"rt.tflite")
print("orig sha",sha(ORIG)); print("roundtrip sha",sha(OUT+"rt.tflite"),"bytes identical:",open(ORIG,'rb').read()==open(OUT+"rt.tflite",'rb').read(), os.path.getsize(ORIG),os.path.getsize(OUT+"rt.tflite"))
# data bytes of every tensor identical
a=Model.load(ORIG); b=Model.load(OUT+"rt.tflite")
same=all(bytes(bytearray(x.data if x.data is not None else []))==bytes(bytearray(y.data if y.data is not None else [])) for x,y in zip(a.m.buffers,b.m.buffers))
print("all buffers equal:",same,len(a.m.buffers))
d=load_cache(); X=d["X0"][::7]  # 65 rows spanning all conds/photos
P1=run_model(ORIG,X);P2=run_model(OUT+"rt.tflite",X)
print("n rows",len(X),"max abs diff orig vs roundtrip:",np.abs(P1-P2).max())
# (iii) stem bias & weight edit changes pre-activation (read stem output tensor 116 = conv out, float)
def stem(path,x):
    it=tf.lite.Interpreter(model_path=path,experimental_preserve_all_tensors=True);it.allocate_tensors()
    it.set_tensor(it.get_input_details()[0]['index'],x[None]);it.invoke();return it.get_tensor(116)[0]
x=d["X0"][0]
base=stem(ORIG,x)
m=Model.load(ORIG); bb=m.get(1); bb[14]-=0.5; m.set(1,bb); m.save(OUT+"b14.tflite")
s=stem(OUT+"b14.tflite",x); dd=s-base
print("bias ch14 -0.5: mean change ch14",dd[...,14].mean(),"max |change| other channels",np.abs(np.delete(dd,14,axis=-1)).max())
m=Model.load(ORIG); w=m.get(54); sc=m.quant_op_for_weight(54)[0]
w[14,:,:,0]-=2*sc  # lower red weights at all 9 taps by 2 grid steps
m.set(54,w); m.save(OUT+"w14.tflite")
s=stem(OUT+"w14.tflite",x); dd=s-base
# predicted: delta pre = -2sc * (2*R-1)  summed over 3x3 window -> check at interior position
xin=x*2-1; k=(10,10); pred=-2*sc*xin[2*k[0]-1:2*k[0]+2,2*k[1]-1:2*k[1]+2,0].sum()  # stride2 SAME pad: top-left offset
print("weight ch14 R -2 steps: observed change interior",dd[k[0],k[1],14],"mean change",dd[...,14].mean(),"others max",np.abs(np.delete(dd,14,axis=-1)).max())
print("shared-buffer check for tensors 1,54:",m.shared(1),m.shared(54))
# off-grid / out-of-range behaviour
m=Model.load(ORIG); w=m.get(54); w[14,1,1,0]+=0.003; m.set(54,w); m.save(OUT+"off.tflite")
print("off-grid +0.003 (0.3 step) effect:",np.abs(stem(OUT+"off.tflite",x)-base).max()," (0 => rounded away)")
w=m.get(54); w[14,1,1,0]=3.0; m.set(54,w); m.save(OUT+"clip.tflite")
print("out-of-range 3.0 -> clipped to", m.quant_op_for_weight(54)[5])
