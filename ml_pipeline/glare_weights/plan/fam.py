import sys; sys.path.insert(0,'.')
import numpy as np
from exp import *

GRAY=np.ones(3)/3
U=np.array([0.35,0.02,-0.5]); U=U/np.linalg.norm(U)   # warm-cast direction used by glare_lib.warm_cast (multiplicative gains)

def snap(m,w):
    sc,zp,qmin,qmax,lo,hi=m.quant_op_for_weight(54)
    q=np.clip(np.round(w/sc),qmin-zp,qmax-zp); return (q*sc).astype(np.float32)

def bias_shift(d):
    def f(m):
        b=m.get(1)
        for c,v in d.items(): b[c]+=v
        m.set(1,b); return dict(tensor=1,bias=d)
    return f

def chroma_damp(chs,alpha,bias_comp=False):
    """w' = gray_part + (1-alpha)*chroma_part per tap, per channel (gray_part = mean(rgb) on each of R,G,B)."""
    def f(m):
        w=m.get(54); n=0
        for c in chs:
            g=w[c].mean(-1,keepdims=True)*np.ones(3); w[c]=g+(1-alpha)*(w[c]-g)
        m.set(54,snap(m,w)); return dict(tensor=54,chs=list(chs),alpha=alpha)
    return f

def warm_proj(chs,alpha):
    """remove fraction alpha of the component of each tap's RGB weight along the warm-cast direction U."""
    def f(m):
        w=m.get(54)
        for c in chs:
            comp=(w[c]@U)[...,None]*U
            w[c]=w[c]-alpha*comp
        m.set(54,snap(m,w)); return dict(tensor=54,chs=list(chs),alpha=alpha)
    return f

def dw_gain(chs,gain):
    """scale first depthwise conv weights (tensor 56 [1,3,3,32]) of the given stem channels."""
    def f(m):
        w=m.get(56)
        for c in chs: w[...,c]*=gain
        m.set(56,snap2(m,w,56)); return dict(tensor=56,chs=list(chs),gain=gain)
    return f
def snap2(m,w,idx):
    sc,zp,qmin,qmax,lo,hi=m.quant_op_for_weight(idx)
    return (np.clip(np.round(w/sc),qmin-zp,qmax-zp)*sc).astype(np.float32)

if __name__=="__main__":
    which=sys.argv[1]
    if which=="bias":
        for nm,d in [("b14 -0.25",{14:-.25}),("b14 -0.5",{14:-.5}),("b14 -1.0",{14:-1.0}),("b21 +0.5",{21:.5}),("b14-.5 b21+.5",{14:-.5,21:.5})]:
            run(nm,bias_shift(d))
    if which=="damp":
        S=[14,21,12,0,16,31,24]
        for nm,fn in [("damp14 .5",chroma_damp([14],.5)),("damp14 1.0",chroma_damp([14],1.0)),("damp7 .5",chroma_damp(S,.5)),("damp7 1.0",chroma_damp(S,1.0)),
                      ("warmproj14 1.0",warm_proj([14],1.0)),("warmproj7 1.0",warm_proj(S,1.0)),("warmprojall .5",warm_proj(range(32),.5))]:
            run(nm,fn)
    if which=="dw":
        for nm,fn in [("dw14 .5",dw_gain([14],.5)),("dw14 .0",dw_gain([14],0.0)),("dw14,21 .5",dw_gain([14,21],.5))]:
            run(nm,fn)
