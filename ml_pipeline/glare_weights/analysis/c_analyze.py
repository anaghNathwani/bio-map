import pickle,numpy as np,json
D=pickle.load(open("collect.pkl","rb")); res=D['res']; meta=D['meta']; lay=D['layers']; L=D['lab']
conds=["golden","veil","backlit","silhouette"]
truth=np.array([L[m[1]] for m in meta]); N=len(truth)
R="/Users/anagh/important/congressional/birdmap/ios/BioMap/BioMap/ML/Bundled/"
labels=json.load(open(R+"BundledBirdLabels.json"))
print("== C: per-layer drift. relative drift = ||mean_ch(glare)-mean_ch(clean)|| / ||mean_ch(clean)|| (avg over images); sat% = frac of positions at upper range; dead% = channels zero everywhere")
print("idx op           hi    | sat clean | "+" | ".join(f"{c[:4]} rel sat dead" for c in conds))
def agg(c,k,j): return np.stack([r[k][j] for r in res[c]['layers']])  # N x C
for (k,op,lo,hi) in lay:
    if k not in res['clean']['layers'][0]: continue
    if not (k%4==0 or op=='ADD' or k>290): continue
    mc=agg('clean',k,0); row=f"{k:3d} {op[:9]:9s} {hi if hi else 0:6.1f} | {agg('clean',k,1).mean()*100:5.2f} | "
    for c in conds:
        mg=agg(c,k,0); rel=np.mean(np.linalg.norm(mg-mc,axis=1)/(np.linalg.norm(mc,axis=1)+1e-9))
        dead=(agg(c,k,2).min(0)>0.999).mean()*100
        row+=f"{rel:.2f} {agg(c,k,1).mean()*100:5.2f} {dead:4.1f} | "
    print(row)
# pooled features & head
import tensorflow as tf
it=tf.lite.Interpreter(model_path=R+"BundledBirdModel.tflite");it.allocate_tensors()
W=it.get_tensor(53);b=it.get_tensor(111)
print("\n== D: outcomes (n=%d dev images per condition)"%N)
Pc=np.array(res['clean']['prob'])
for c in ["clean"]+conds:
    P=np.array(res[c]['prob']);top=P.argmax(1);conf=P.max(1);ok=top==truth
    bg=(top==964);shown=ok&(conf>=.5)
    wrong_shown=(~ok)&(conf>=.5)&(~bg)
    f=np.array(res[c]['pool']);lg=f@W.T+b
    m=lg[np.arange(N),truth]-np.where(np.eye(965,dtype=bool)[truth],-1e9,lg).max(1)
    print(f"{c:10s} top1 {ok.mean():.2f} shown-right {shown.mean():.2f} conf<0.5 {(conf<.5).mean():.2f} bgwins {bg.mean():.2f} wrong-shown {wrong_shown.mean():.2f} mean conf {conf.mean():.2f} true margin(logit) {m.mean():+.2f} bg-logit-minus-true {np.mean(lg[:,964]-lg[np.arange(N),truth]):+.2f}  mean|pool| {np.abs(f).mean():.3f} mean max logit {lg.max(1).mean():.2f}")
# decomposition: swap clean pooled features with glare features? margin = W_t.f - max.. ; feature vs head: head fixed so all in features. evidence by channel
fc=np.array(res['clean']['pool'])
print("\ntrue-class evidence channels: contribution W[true,c]*f[c], top 15 channels by mean clean contribution; their change")
contrib=lambda f:(W[truth]*f)   # N x 1280
cc=contrib(fc).mean(0); top=np.argsort(-cc)[:15]
tot_clean=contrib(fc).sum(1)
for c in conds:
    f=np.array(res[c]['pool']); cg=contrib(f)
    print(c,"true-logit contrib sum clean %.2f -> %.2f; top15 chans %.2f -> %.2f; mean ratio feature(glare)/clean over top15 %.2f; global mean pooled feat clean %.3f glare %.3f; corr(delta feature) ..."%(tot_clean.mean(),cg.sum(1).mean(),cc[top].sum(),cg.mean(0)[top].sum(),np.mean(f[:,top].mean(0)/fc[:,top].mean(0)),fc.mean(),f.mean()))
# attractors
print("\nattractors: classes predicted when wrong (glare), count, with bias rank")
bias_rank=np.argsort(np.argsort(-b))
for c in conds:
    P=np.array(res[c]['prob']);top=P.argmax(1);w=top[top!=truth]
    u,n=np.unique(w,return_counts=True);o=np.argsort(-n)[:6]
    print(c,"wrong n=%d;"%len(w),[(labels[u[i]],int(n[i]),round(float(b[u[i]]),2)) for i in o],"| mean bias of wrong-preds %.2f vs population 0.016; mean bias rank %.0f"%(b[w].mean(),bias_rank[w].mean()))
# hypothesis tests (in-memory, head only, no refit): lower bg bias / equalise bias
print("\nH1: lower bg bias by delta (head-only edit in memory)")
for delta in [0,1,2,3,4.95]:
    row=[]
    for c in ["clean"]+conds:
        f=np.array(res[c]['pool']);lg=f@W.T+b;lg[:,964]-=delta
        p=np.exp(lg-lg.max(1,keepdims=True));p/=p.sum(1,keepdims=True)
        top=p.argmax(1);conf=p.max(1);row.append("%s top1 %.2f shown %.2f"%(c[:4],(top==truth).mean(),((top==truth)&(conf>=.5)).mean()))
    print(delta,"; ".join(row))
print("H2: subtract k*(bias-mean) from species biases (flatten bias), k=")
for k in [0,.5,1]:
    row=[]
    for c in ["clean"]+conds:
        f=np.array(res[c]['pool']);bb=b.copy();bb[:964]-=k*(b[:964]-b[:964].mean());lg=f@W.T+bb
        p=np.exp(lg-lg.max(1,keepdims=True));p/=p.sum(1,keepdims=True)
        top=p.argmax(1);conf=p.max(1);wr=((top!=truth)&(conf>=.5)&(top!=964)).mean();row.append("%s top1 %.2f shown %.2f wrongshown %.2f"%(c[:4],(top==truth).mean(),((top==truth)&(conf>=.5)).mean(),wr))
    print(k,"; ".join(row))
# per-layer channel mean shift: which stem channels change most
k0=[l[0] for l in lay][0]
mc=agg('clean',k0,0).mean(0)
for c in conds: print("stem ch mean shift",c,np.round((agg(c,k0,0).mean(0)-mc),2)[[0,12,14,16,21,24,31]],"(ch 0,12,14,16,21,24,31)")
