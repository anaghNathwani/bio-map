"""Poster 06, "Something lurks around the corner." Same black-and-white, dots-and-serif language as the
"Look up." posters, and the same idea turned over: the living world isn't only up in the sky, it is also
small, close and just out of sight. A stippled microbe (the Paramecium outline from web/scripts/gen_organisms.py,
the same shapes the BioMap loader morphs through) is half hidden behind the edge of a wall.
No app, no features: sign-off is the bird mark and BIOMAP.

  python3 build_lurk.py        # writes posters/06-lurks-4x5.png and posters/06-lurks-story.png
Needs playwright (system Chrome).
"""
import json, pathlib, re

HERE = pathlib.Path(__file__).parent
SRC = HERE / 'src'
FONTS = '../../social/instagram/src/fonts'
ORG = HERE.parent.parent / 'web' / 'src' / 'lib' / 'organisms.js'
BIRD = "M6 27C11 14 21 7 34 7c2.7 0 5 .4 7 1.1-1.8 1-3.3 2.3-4.4 4C40 12.4 43 13.4 45 15.3c-3 .3-5.6 1.4-7.7 3.2 1 6.7-1.2 13-6.4 17.6C25.8 41.4 18.8 43.6 11 42.4c3.6-1 6.6-2.9 8.8-5.5-5-.4-9.4-3-12.2-7.1 2.6.7 5.1.6 7.4-.4C11 27.8 7.9 25 6 21.2"


def radii(name):
    m = re.search(r'name: "%s", r: \[([^\]]+)\]' % name, ORG.read_text())
    return [float(x) for x in m.group(1).split(',')]


def html(w, h):
    r = radii('Paramecium')
    cfg = dict(w=w, h=h, r=r,
               edge=.60,            # x of the wall's edge, as a fraction of width
               cx=.70, cy=.25,      # organism centre (behind the wall), fractions
               size=.40)            # organism radius as a fraction of width
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
<div class="p">Something lurks<br><em>around the corner.</em><div class="s">Older than every bird. Smaller than a grain of sand.</div></div>
<div class="foot"><svg viewBox="0 0 48 48" width="{int(w*.045)}" height="{int(w*.045)}" fill="none" stroke="#fff" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="{BIRD}"/><circle cx="33.5" cy="14.5" r="1.4" fill="#fff" stroke="none"/></svg><span>BIOMAP</span></div>
<script>
const C={json.dumps(cfg)};
const ctx=document.getElementById('cv').getContext('2d');
const rnd=(s=>()=>{{s|=0;s=s+0x6D2B79F5|0;let t=Math.imul(s^s>>>15,1|s);t=t+Math.imul(t^t>>>7,61|t)^t;return((t^t>>>14)>>>0)/4294967296}})(6);
const W=C.w,H=C.h,N=C.r.length;
const cx=C.cx*W,cy=C.cy*H,R=C.size*W,edge=C.edge*W;
// radius at angle (linear interpolation of the sampled outline), plus one long pseudopod reaching round the edge
function rad(t){{
  t=((t%(2*Math.PI))+2*Math.PI)%(2*Math.PI);
  const f=t/(2*Math.PI)*N,i=Math.floor(f)%N,j=(i+1)%N,u=f-Math.floor(f);
  let r=C.r[i]*(1-u)+C.r[j]*u;
  const d=((t-Math.PI+Math.PI)%(2*Math.PI)+2*Math.PI)%(2*Math.PI); // angle 0 = +x; pseudopod points to -x (left, past the edge)
  const dd=Math.min(Math.abs(t-Math.PI),2*Math.PI-Math.abs(t-Math.PI));
  return R*(r+.55*Math.exp(-((dd/.34)**2)));
}}
function inside(x,y){{const dx=x-cx,dy=y-cy;return Math.hypot(dx,dy)<rad(Math.atan2(dy,dx))}}
ctx.fillStyle='#000';ctx.fillRect(0,0,W,H);
// stipple fill: denser towards the outline, so it reads as a translucent body
let placed=0;
for(let k=0;k<400000&&placed<9000;k++){{
  const x=cx-R*1.6+rnd()*R*2.2,y=cy-R*1.1+rnd()*R*2.2;
  if(!inside(x,y))continue;
  const dx=x-cx,dy=y-cy,a=Math.atan2(dy,dx),q=Math.hypot(dx,dy)/rad(a);
  if(rnd()>Math.pow(q,2.6)*.9+.05)continue;
  ctx.fillStyle=`rgba(255,255,255,${{.25+.55*q}})`;
  ctx.beginPath();ctx.arc(x,y,1.1+rnd()*1.3,0,7);ctx.fill();placed++;
}}
// outline as a string of dots
for(let i=0;i<1400;i++){{
  const t=i/1400*2*Math.PI,r=rad(t)*(1+(rnd()-.5)*.012);
  ctx.fillStyle='rgba(255,255,255,.9)';ctx.beginPath();ctx.arc(cx+r*Math.cos(t),cy+r*Math.sin(t),1.7,0,7);ctx.fill();
}}
// nucleus: a ring of dots and a bright core
for(let i=0;i<260;i++){{const t=rnd()*7,rr=R*.13*Math.sqrt(rnd());ctx.fillStyle='rgba(255,255,255,.85)';ctx.beginPath();ctx.arc(cx-R*.12+rr*Math.cos(t),cy+rr*Math.sin(t),1.4,0,7);ctx.fill();}}
// the wall: everything right of its edge hides the body; a slightly lifted black with a hairline edge
const wg=ctx.createLinearGradient(edge,0,W,0);wg.addColorStop(0,'#141414');wg.addColorStop(1,'#050505');
ctx.fillStyle=wg;ctx.fillRect(edge,0,W-edge,H*.47);
ctx.fillStyle='#000';ctx.fillRect(edge,H*.47,W-edge,H);   // the wall stops; below it is open dark
ctx.strokeStyle='rgba(255,255,255,.55)';ctx.lineWidth=2;
ctx.beginPath();ctx.moveTo(edge,0);ctx.lineTo(edge,H*.47);ctx.stroke();
// the floor line where the wall meets the ground
ctx.strokeStyle='rgba(255,255,255,.22)';ctx.beginPath();ctx.moveTo(edge,H*.47);ctx.lineTo(W,H*.47);ctx.stroke();
// soft shadow thrown from the wall's edge across the dark
const sg=ctx.createLinearGradient(edge-W*.18,0,edge,0);sg.addColorStop(0,'rgba(0,0,0,0)');sg.addColorStop(1,'rgba(0,0,0,.35)');
ctx.fillStyle=sg;ctx.fillRect(edge-W*.18,0,W*.18,H*.47);
</script></body></html>'''


def main():
    from playwright.sync_api import sync_playwright
    with sync_playwright() as p:
        b = p.chromium.launch(channel='chrome')
        pg = b.new_page()
        for w, h, tag in [(1080, 1350, '4x5'), (1080, 1920, 'story')]:
            f = SRC / f'poster-06-lurks-{tag}.html'
            f.write_text(html(w, h))
            pg.set_viewport_size({'width': w, 'height': h})
            pg.goto(f.as_uri()); pg.evaluate('document.fonts.ready'); pg.wait_for_timeout(400)
            out = HERE / 'posters' / f'06-lurks-{tag}.png'
            pg.screenshot(path=str(out), type='png'); print('wrote', out.name)
        b.close()


if __name__ == '__main__':
    main()
