import sys; sys.path.insert(0,'.')
import numpy as np
from tflite_edit import *
m=Model.load("/Users/anagh/important/congressional/birdmap/ios/BioMap/BioMap/ML/Bundled/BundledBirdModel.tflite")
print(len(m.sg.tensors),"tensors", len(m.sg.operators),"ops")
for i in (1,54,56): print(i,m.name(i),m.sg.tensors[i].shape,"buf",m.sg.tensors[i].buffer,"shared",m.shared(i))
w=m.get(54); print(w.shape, m.quant_op_for_weight(54))
q=m.quant_op_for_weight(54); sc=q[0]
print("on grid:",np.abs(w/sc-np.round(w/sc)).max(), "range",w.min(),w.max())
# stem is first conv: weights layout [out,kh,kw,in]
print("bias",np.round(m.get(1),2))
# next layer: first depthwise (tensor 56) and what follows
for i in range(0,20):
    pass
print([ (i,m.name(i)) for i in range(50,60)])
