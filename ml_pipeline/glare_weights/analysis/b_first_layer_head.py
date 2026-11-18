import tensorflow as tf, numpy as np, json
R="/Users/anagh/important/congressional/birdmap/ios/BioMap/BioMap/ML/Bundled/"
it=tf.lite.Interpreter(model_path=R+"BundledBirdModel.tflite"); it.allocate_tensors()
labels=json.load(open(R+"BundledBirdLabels.json"))
W=it.get_tensor(54); b=it.get_tensor(1)   # (32,3,3,3) OHWI, bias(32); input is x*2-1
# per-channel colour weight sums over the 3x3 window
S=W.sum(axis=(1,2))       # (32,3) R,G,B
print("distinct weight grid step:",np.unique(np.round(np.diff(np.unique(W)),4))[:5])
# uniform input shift in [0,1] space by (dr,dg,db): pre-activation change = 2*S.d
def dpre(d): return 2*S@np.array(d)
cases={"warm cast R*1.3,B*0.6 @x=.5":[.15,0,-.2],"brightness +0.2":[.2,.2,.2],"R up .1":[.1,0,0],"B down .2":[0,0,-.2]}
tot=np.abs(S).sum(1)
dc=S/ (np.abs(S).sum(1,keepdims=True)+1e-9)
print("ch: sumR sumG sumB | bias | |S|/L1 (DC-sensitivity) | luminance-vs-chroma")
lum=np.array([.2126,.7152,.0722])
rows=[]
for c in range(32):
    s=S[c]; l1=np.abs(W[c]).sum()
    rows.append((c,*s.round(2),round(float(b[c]),2),round(float(np.abs(s).sum()/l1),2)))
for r in rows: print(r)
print("median DC-sensitivity |sum|/L1:",np.median([r[-1] for r in rows]))
# fraction of channels whose colour-sum is ~achromatic (edge/texture) vs coloured
chrom=np.linalg.norm(S-np.outer(S@np.ones(3)/3,np.ones(3)),axis=1); dcm=np.abs(S.sum(1))/3
print("channels with |R-B| sum >0.5:",int((np.abs(S[:,0]-S[:,2])>0.5).sum()),"; DC-dominant (|mean|>chrom):",int((dcm>chrom/np.sqrt(3)).sum()))
for k,d in cases.items():
    dp=dpre(d); print(k,"mean|dpre|",round(float(np.abs(dp).mean()),3),"max",round(float(np.abs(dp).max()),2),"#ch |dpre|>0.5:",int((np.abs(dp)>.5).sum()),"n bias<0 ch moved >0.2 up:",int(((dp>.2)).sum()))
# head
Wl=it.get_tensor(53); bl=it.get_tensor(111)
print("head W",Wl.shape,"bias stats",bl.mean(),bl.std(),bl.min(),bl.max())
bg=964
print("bg bias",bl[bg],"rank",int((bl>bl[bg]).sum()),"bg wnorm",np.linalg.norm(Wl[bg]),"rank by wnorm",int((np.linalg.norm(Wl,axis=1)>np.linalg.norm(Wl[bg])).sum()))
n=np.linalg.norm(Wl,axis=1); print("wnorm mean/std",n.mean(),n.std())
print("top bias classes",[(labels[i],round(float(bl[i]),2)) for i in np.argsort(-bl)[:8]])
print("top wnorm classes",[(labels[i],round(float(n[i]),2)) for i in np.argsort(-n)[:8]])
# mean feature direction: does the common-mode (mean over classes) of W have large norm?
m=Wl.mean(0); print("class-mean weight vec norm",np.linalg.norm(m),"vs mean per-class norm",n.mean())
U,s,Vt=np.linalg.svd(Wl-m,full_matrices=False); print("head SV top8",s[:8].round(2),"energy top1/5/20",[(s[:k]**2).sum()/(s**2).sum() for k in(1,5,20)])
np.save("first_layer_S.npy",S)
