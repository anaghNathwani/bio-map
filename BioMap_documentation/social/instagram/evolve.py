"""The "BirdMap is now BioMap" story reel (1080x1920, ~28 s) -> testflight/ (next to the TestFlight ad).

Same pipeline and Apple-style look as testflight.py. The bird mark morphs through other organisms (the
same outlines as the website/app loader), then the old name is struck through and BioMap writes in.
It tells the "why" of the rename (the idea outgrew birds) and makes no claim about what the app does
or where it's headed.

  python3 evolve.py        # renders testflight/birdmap-is-now-biomap.mp4 + -cover.png
"""
import json, pathlib
import audio
import build
import testflight as tf

HERE = pathlib.Path(__file__).parent
OUT = HERE / 'testflight'
NAME = 'birdmap-is-now-biomap'
DUR = 24.8
HOLD, MORPH = 0.3, 0.6          # seconds per organism: pause, then morph

CSS = tf.CSS + """
.draw{stroke-dasharray:1;stroke-dashoffset:1}
.word{font-size:250px;font-weight:700;letter-spacing:-.045em;line-height:1}
.center{position:absolute;left:0;right:0;text-align:center}
h1.c{text-align:center}
"""

JS = r"""
const ORG=__ORG__, HOLD=__HOLD__, MORPH=__MORPH__;
const $=id=>document.getElementById(id);
const vis=(t,a,b)=>ease(seg(t,a,.6))*(1-ease(seg(t,b,.5)));
function contour(r,S,R){const n=r.length,c=S/2,P=r.map((v,i)=>{const a=2*Math.PI*i/n;return[c+v*R*Math.cos(a),c-v*R*Math.sin(a)]});
  let d='M'+P[0][0].toFixed(2)+' '+P[0][1].toFixed(2);
  for(let i=0;i<n;i++){const p0=P[(i-1+n)%n],p1=P[i],p2=P[(i+1)%n],p3=P[(i+2)%n];
    d+='C'+(p1[0]+(p2[0]-p0[0])/6).toFixed(2)+' '+(p1[1]+(p2[1]-p0[1])/6).toFixed(2)+' '+(p2[0]-(p3[0]-p1[0])/6).toFixed(2)+' '+(p2[1]-(p3[1]-p1[1])/6).toFixed(2)+' '+p2[0].toFixed(2)+' '+p2[1].toFixed(2)}
  return d+'Z'}
window.custom=function(t){
  // the morph stage: visible 3.6 -> 12.4
  const m=$('stage'); m.style.opacity=vis(t,3.6,12.2);
  const lt=Math.max(0,t-3.8), cyc=HOLD+MORPH, step=Math.floor(lt/cyc), within=lt-step*cyc, n=ORG.length;
  const i0=Math.min(step,n-1), i1=Math.min(step+1,n-1);
  const raw=within<HOLD?0:(within-HOLD)/MORPH, e=raw<.5?4*raw*raw*raw:1-Math.pow(-2*raw+2,3)/2;
  const from=ORG[i0], to=ORG[i1];
  const rr=from.r.map((v,i)=>v+(to.r[i]-v)*e);
  $('mpath').setAttribute('d',contour(rr,700,290));
  const na=i0>=5?1:0, nb=i1>=5?1:0; $('mnuc').setAttribute('opacity',na+(nb-na)*e);
  $('mname').textContent=(e>.5?to:from).name;
};
"""


def page():
    body = ''
    # 1. the beginning: a bird
    body += ('<div class="abs" data-a=".1" data-b="3.2" data-y="0" style="left:0;right:0;top:360px;display:flex;justify-content:center">'
             + build.bird(330, draw=True, color='#1D1D1F', sw=2.1).replace('class="draw"', 'class="draw" data-a=".2" data-d="1.4"') + '</div>')
    body += ('<div class="center" style="top:820px" data-a=".7" data-b="3.2" data-d=".9"><div class="word">BirdMap</div></div>')
    body += ('<div class="center" style="top:1130px;font-size:56px;color:#6E6E73;letter-spacing:-.02em" data-a="1.4" data-b="3.2" data-d=".8">It started with a bird.</div>')
    # 2. the morph
    body += ('<div id="stage" class="abs" style="left:0;right:0;top:0;bottom:0;opacity:0">'
             '<svg class="abs" style="left:190px;top:640px;overflow:visible" width="700" height="700" viewBox="0 0 700 700">'
             '<path id="mpath" d="" fill="none" stroke="#0071E3" stroke-width="7" stroke-linejoin="round"/>'
             '<circle id="mnuc" cx="350" cy="350" r="26" fill="#0071E3" opacity="0"/></svg>'
             '<div id="mname" class="center" style="top:1390px;font-size:48px;font-weight:600;color:#6E6E73;letter-spacing:-.01em">Bird</div></div>')
    body += ('<div class="abs" style="left:100px;right:100px;top:200px" data-a="3.7" data-b="7.7" data-d=".8"><h1>Then the dream kept growing.</h1></div>')
    body += ('<div class="abs" style="left:100px;right:100px;top:200px" data-a="7.9" data-b="12.0" data-d=".8"><h1>Past wings, to <span style="color:#0071E3">all kinds of life.</span></h1></div>')
    # 3. the name flips
    strike = ('<svg height="40" viewBox="0 0 920 40" preserveAspectRatio="none" fill="none" stroke="#0071E3" stroke-width="9" stroke-linecap="round" '
              'style="position:absolute;left:-30px;width:calc(100% + 60px);top:104px;overflow:visible">'
              '<path pathLength="1" class="draw" data-a="13.6" data-d=".7" vector-effect="non-scaling-stroke" d="M10 22 C230 8 520 34 910 16"/></svg>')
    body += ('<div class="abs" style="left:100px;right:100px;top:200px" data-a="12.6" data-b="16.4" data-d=".8"><h1>So we&rsquo;re changing our name.</h1></div>')
    body += (f'<div class="center" style="top:760px" data-a="12.9" data-b="16.4" data-y="0" data-d=".7"><div style="position:relative;display:inline-block" class="word"><span style="color:#8E8E93">BirdMap</span>{strike}</div></div>')
    body += ('<div class="center" style="top:1010px" data-a="14.5" data-b="16.4" data-y="40" data-d=".8"><div class="word" style="font-size:300px">Bio<span style="color:#0071E3">Map</span></div></div>')
    # 4. what stays the same
    body += ('<div class="abs" style="left:100px;right:100px;top:560px" data-a="16.6" data-b="20.4" data-d=".8">'
             '<h1>Same community.<br>Same sightings.<br><span style="color:#0071E3">New name.</span></h1></div>')
    # 5. end card
    body += ('<div class="abs" style="left:100px;right:100px;top:420px" data-a="20.6" data-d=".8">'
             '<div class="eyebrow">The public beta is open</div>'
             '<h1 style="margin-top:18px">Say hello to BioMap.</h1>'
             '<div class="sub">Join on TestFlight.</div>'
             f'<span class="linkpill" style="font-size:41px;padding:34px 48px">{tf.LINK_SHORT}</span></div>')
    body += ('<div class="abs" style="left:100px;right:100px;top:1480px;display:flex;align-items:center;gap:18px;font-size:40px;font-weight:700;letter-spacing:-.02em" data-a="21.8" data-d=".6" data-y="0">'
             + build.bird(60, color='#1D1D1F', sw=2.4) + 'BioMap</div>')
    js = JS.replace('__ORG__', json.dumps(tf.ORGANISMS)).replace('__HOLD__', str(HOLD)).replace('__MORPH__', str(MORPH))
    return (f'<!doctype html><html><head><meta charset="utf-8"><style>{CSS}</style></head><body>{body}'
            f'<script>{build.TL_JS}{js}</script></body></html>')


def main():
    from playwright.sync_api import sync_playwright
    OUT.mkdir(exist_ok=True)
    with sync_playwright() as p:
        b = p.chromium.launch(channel='chrome')
        pg = b.new_page(viewport={'width': 1080, 'height': 1920})
        mp4 = OUT / f'{NAME}.mp4'
        build.render_reel(pg, NAME, page(), DUR, mp4)
        audio.add_audio(mp4)
        pg.set_viewport_size({'width': 1080, 'height': 1920})
        pg.goto((build.SRC / f'reel-{NAME}.html').as_uri()); pg.evaluate('document.fonts.ready'); pg.wait_for_timeout(200)
        pg.evaluate('render(15.6)')   # cover = the name reveal
        pg.screenshot(path=str(OUT / f'{NAME}-cover.png'), type='png')
        b.close()


if __name__ == '__main__':
    main()
