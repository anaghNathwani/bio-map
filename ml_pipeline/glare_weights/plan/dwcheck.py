import sys; sys.path.insert(0,'.')
import numpy as np
from tflite_edit import *
from devlib import ORIG
m=Model.load(ORIG); w=m.get(56); n=np.abs(w).sum((0,1,2)); sc=m.quant_op_for_weight(56)
print("dw tensor 56 scale/zp",sc[:2]); print("L1 per stem channel:\n",np.round(n,2))
dead=[1,2,6,7,8,9,10,11,15,19,30]; print("dead-channel L1:",np.round(n[dead],3))
for c in (14,21,12,0,16,31,24): print(c,"nonzero taps",int((w[...,c]!=0).sum()),"L1",round(float(n[c]),3))
