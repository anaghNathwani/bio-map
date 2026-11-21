"""Poster 07, "Something lurks around the corner... more than one." Companion to 06 (build_lurk.py): same wall, same
stipple, but what peeks round the edge is a small flock of the BioMap bird, and three of them are caught in
viewfinder brackets while the fainter ones behind haven't been noticed yet. A visual hint of finding several birds in one
frame, with no words about the app or its features. Sign-off is the bird mark and BIOMAP.

  python3 build_lurk_flock.py     # writes posters/07-lurks-flock-4x5.png and -story.png
"""
import json, pathlib

HERE = pathlib.Path(__file__).parent
SRC = HERE / 'src'
FONTS = '../../social/instagram/src/fonts'
BIRD = "M6 27C11 14 21 7 34 7c2.7 0 5 .4 7 1.1-1.8 1-3.3 2.3-4.4 4C40 12.4 43 13.4 45 15.3c-3 .3-5.6 1.4-7.7 3.2 1 6.7-1.2 13-6.4 17.6C25.8 41.4 18.8 43.6 11 42.4c3.6-1 6.6-2.9 8.8-5.5-5-.4-9.4-3-12.2-7.1 2.6.7 5.1.6 7.4-.4C11 27.8 7.9 25 6 21.2"

# x (fraction of W), y (fraction of wall height), size (fraction of W), brightness, bracketed
BIRDS = [(.545, .27, .30, 1.0, True), (.33, .60, .21, 1.0, True), (.585, .88, .22, 1.0, True),
         (.26, .22, .12, .55, False), (.22, .90, .09, .45, False), (.43, .98, .07, .4, False)]


def html(w, h):
    cfg = dict(w=w, h=h, edge=.60, wall=.47, bird=BIRD, birds=BIRDS)
    fs = w * .108
    return f'''<!doctype html><html><head><meta charset="utf-8"><style>
@font-face{{font-family:F;src:url({FONTS}/fraunces-latin-standard-normal.woff2);font-weight:100 900}}
@font-face{{font-family:F;font-style:italic;src:url({FONTS}/fraunces-latin-wght-italic.woff2);font-weight:100 900}}
@font-face{{font-family:G;src:url({FONTS}/geist-latin-wght-normal.woff2);font-weight:100 900}}
*{{margin:0;padding:0;box-sizing:border-box}}
html,body{{width:{w}px;height:{h}px;overflow:hidden;background:#000}}
canvas{{position:absolute;inset:0}}
.p{{position:absolute;left:8%;right:8%;bottom:{h*.115:.0f}px;font-family:F,serif;color:#fff;font-size:{fs:.0f}px;line-height:1.04;letter-spacing:-.02em}}
.p em{{font-style:italic}}
.s{{font-family:G,sans-serif;font-size:{w*.032:.0f}px;line-height:1.5;color:#9b968a;margin-top:{h*.02:.0f}px;letter-spacing:.01em;max-width:80%}}
.foot{{position:absolute;left:8%;right:8%;bottom:{h*.045:.0f}px;display:flex;align-items:center;gap:16px;font-family:G,sans-serif;font-size:{w*.022:.0f}px;letter-spacing:.24em;color:#9b968a}}
</style></head><body><canvas id="cv" width="{w}" height="{h}"></canvas>
<div class="p">Something lurks<br><em>around the corner.</em><div class="s">Look closer. There is more than one.</div></div>
<div class="foot"><svg viewBox="0 0 48 48" width="{int(w*.045)}" height="{int(w*.045)}" fill="none" stroke="#fff" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="{BIRD}"/><circle cx="33.5" cy="14.5" r="1.4" fill="#fff" stroke="none"/></svg><span>BIOMAP</span></div>
<script>
const C={json.dumps(cfg)};
const ctx=document.getElementById('cv').getContext('2d');
const rnd=(s=>()=>{{s|=0;s=s+0x6D2B79F5|0;let t=Math.imul(s^s>>>15,1|s);t=t+Math.imul(t^t>>>7,61|t)^t;return((t^t>>>14)>>>0)/4294967296}})(9);
const W=C.w,H=C.h,edge=C.edge*W,wallH=C.wall*H,path=new Path2D(C.bird);
ctx.fillStyle='#000';ctx.fillRect(0,0,W,H);
for(const [fx,fy,fs,br,boxed] of C.birds){{
  const cx=fx*W,cy=fy*wallH,size=fs*W,s=size/40;        // bird mark spans ~40 units
  // mirrored so the birds look back out from behind the wall; (24,25) is the mark's centre
  const set=()=>ctx.setTransform(-s,0,0,s,cx+24*s,cy-25*s);
  set();
  let n=0;
  for(let k=0;k<200000&&n<size*22;k++){{
    const x=cx-size*.6+rnd()*size*1.2,y=cy-size*.6+rnd()*size*1.2;
    if(x>edge||!ctx.isPointInPath(path,x,y))continue;
    ctx.setTransform(1,0,0,1,0,0);
    ctx.fillStyle=`rgba(255,255,255,${{(.3+.5*rnd())*br}})`;
    ctx.beginPath();ctx.arc(x,y,.9+rnd()*1.2,0,7);ctx.fill();n++;set();
  }}
  // outline as a dotted line
  ctx.save();ctx.beginPath();ctx.rect(-1e4,-1e4,1e5,1e5);ctx.restore();
  ctx.save();ctx.setTransform(1,0,0,1,0,0);ctx.beginPath();ctx.rect(0,0,edge,H);ctx.clip();set();
  ctx.strokeStyle=`rgba(255,255,255,${{.95*br}})`;ctx.lineCap='round';ctx.lineWidth=3.2/s;ctx.setLineDash([.1/s,5.5/s]);ctx.stroke(path);
  // the eye
  ctx.setLineDash([]);ctx.fillStyle=`rgba(255,255,255,${{br}})`;ctx.beginPath();ctx.arc(33.5,14.5,1.5,0,7);ctx.fill();
  ctx.restore();
  ctx.setTransform(1,0,0,1,0,0);
  if(boxed){{  // viewfinder corners, clipped at the wall
    const b=size*.52,L=size*.12;ctx.save();ctx.beginPath();ctx.rect(0,0,edge,H);ctx.clip();
    ctx.strokeStyle='rgba(255,255,255,.85)';ctx.lineWidth=2.4;ctx.lineCap='square';ctx.beginPath();
    for(const [sx,sy] of [[-1,-1],[1,-1],[-1,1],[1,1]]){{const px=cx+sx*b,py=cy+sy*b;ctx.moveTo(px,py-sy*L);ctx.lineTo(px,py);ctx.lineTo(px-sx*L,py);}}
    ctx.stroke();ctx.restore();
  }}
}}
// the wall
const wg=ctx.createLinearGradient(edge,0,W,0);wg.addColorStop(0,'#141414');wg.addColorStop(1,'#050505');
ctx.fillStyle=wg;ctx.fillRect(edge,0,W-edge,wallH);
ctx.strokeStyle='rgba(255,255,255,.55)';ctx.lineWidth=2;ctx.beginPath();ctx.moveTo(edge,0);ctx.lineTo(edge,wallH);ctx.stroke();
ctx.strokeStyle='rgba(255,255,255,.22)';ctx.beginPath();ctx.moveTo(edge,wallH);ctx.lineTo(W,wallH);ctx.stroke();
</script></body></html>'''


def main():
    from playwright.sync_api import sync_playwright
    with sync_playwright() as p:
        b = p.chromium.launch(channel='chrome')
        pg = b.new_page()
        pg.on('pageerror', lambda e: print('JS error:', e))
        for w, h, tag in [(1080, 1350, '4x5'), (1080, 1920, 'story')]:
            f = SRC / f'poster-07-lurks-flock-{tag}.html'
            f.write_text(html(w, h))
            pg.set_viewport_size({'width': w, 'height': h})
            pg.goto(f.as_uri()); pg.evaluate('document.fonts.ready'); pg.wait_for_timeout(400)
            out = HERE / 'posters' / f'07-lurks-flock-{tag}.png'
            pg.screenshot(path=str(out), type='png'); print('wrote', out.name)
        b.close()


if __name__ == '__main__':
    main()
