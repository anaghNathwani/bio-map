"""The "BioMap is on TestFlight" announcement reel (1080x1920, ~30 s) -> testflight/.

Same pipeline as build.py (an HTML page whose look at time t is a pure function, window.render(t);
Playwright screenshots, ffmpeg encodes, audio.py synthesizes the score) but in the app's current
Apple-style look: system font, light grey / near-black, one blue. A phone mockup walks through the four
steps a tester follows: install TestFlight, open the invite link, Accept + Install, open BioMap.

  python3 testflight.py        # renders testflight/testflight-is-live.mp4 + -cover.png

The mockups are drawn for this ad (generic app icons, no screenshots of Apple's UI), and the BioMap
launch screen uses the same bird-to-microbe morph as the app's loading animation.
"""
import json, pathlib, re, sys
import audio
import build

HERE = pathlib.Path(__file__).parent
OUT = HERE / 'testflight'
LINK = 'https://testflight.apple.com/join/ZcyddckA'
LINK_SHORT = 'testflight.apple.com/join/ZcyddckA'
NAME = 'testflight-is-live'
DUR = 30.0

# ---- timeline (seconds) ---------------------------------------------------------------------------
T_IN, T_OUT = 3.3, 23.7
STEPS = [  # (caption start, caption end)
    (3.6, 8.5), (8.7, 13.3), (13.5, 19.3), (19.5, 23.5)]
SCENES = {'s1': (3.2, 8.6), 's2': (8.4, 13.4), 's3': (13.2, 19.5), 's4': (19.3, 22.1), 's5': (21.9, 23.9)}
TAPS = [  # (time, x, y) in phone-screen points
    (5.7, 182, 202), (11.3, 201, 455), (15.3, 201, 560), (17.3, 201, 560), (20.9, 247.7, 257)]

# The same organism outlines the website and the iOS app use (web/scripts/gen_organisms.py).
_src = (HERE.parents[2] / 'web/src/lib/organisms.js').read_text()
ORGANISMS = [{'name': n, 'r': json.loads(r)} for n, r in re.findall(r'name: "([^"]+)", r: (\[[^\]]+\])', _src)]

CSS = """
:root{--bg:#F5F5F7;--fg:#1D1D1F;--soft:#6E6E73;--blue:#0071E3;--rule:#D2D2D7}
*{box-sizing:border-box;margin:0;padding:0}
html,body{width:100%;height:100%;overflow:hidden;background:var(--bg);color:var(--fg);
  font-family:-apple-system,BlinkMacSystemFont,'SF Pro Display','SF Pro Text','Helvetica Neue',Helvetica,Arial,sans-serif;-webkit-font-smoothing:antialiased}
.abs{position:absolute}
[data-a]{opacity:0}
.eyebrow{font-size:40px;font-weight:600;color:var(--blue);letter-spacing:-.01em}
h1{font-size:112px;font-weight:700;line-height:1.04;letter-spacing:-.035em}
h2{font-size:84px;font-weight:700;line-height:1.05;letter-spacing:-.03em;margin-top:14px}
.sub{font-size:42px;line-height:1.35;color:var(--soft);margin-top:22px;letter-spacing:-.01em}
.cap{position:absolute;left:100px;right:100px;top:140px}
.pillbtn{display:inline-flex;align-items:center;justify-content:center;border-radius:999px;background:var(--blue);color:#fff;font-weight:600;letter-spacing:-.01em}
.linkpill{display:inline-block;margin-top:56px;padding:34px 56px;border-radius:999px;background:var(--blue);color:#fff;font-size:42px;font-weight:600;letter-spacing:-.015em}

/* --- phone --- */
#phone{position:absolute;left:263px;top:450px;width:426px;height:898px;border-radius:70px;background:#1D1D1F;
  box-shadow:0 0 0 2px #3A3A3C inset,0 40px 90px rgba(0,0,0,.28);transform-origin:0 0;padding:12px}
#screen{position:relative;width:402px;height:874px;border-radius:58px;overflow:hidden;background:#fff;font-size:15px;color:#1D1D1F}
.scr{position:absolute;inset:0;background:#fff;opacity:0}
.island{position:absolute;left:141px;top:11px;width:120px;height:35px;border-radius:20px;background:#000;z-index:30}
.status{position:absolute;left:0;right:0;top:0;height:54px;z-index:29;font-size:17px;font-weight:600}
.status .time{position:absolute;left:44px;top:17px}
.status .bat{position:absolute;right:30px;top:21px;width:25px;height:12px;border:1.5px solid #1D1D1F;border-radius:4px}
.status .bat i{position:absolute;left:1.5px;top:1.5px;bottom:1.5px;width:15px;border-radius:2px;background:#1D1D1F}
.status .sig{position:absolute;right:66px;top:24px;display:flex;gap:2px;align-items:flex-end}
.status .sig i{display:block;width:3.5px;background:#1D1D1F;border-radius:1px}
.icon{border-radius:22.5%;display:block}
.gray{background:#F2F2F7}
.bold{font-weight:700;letter-spacing:-.02em}
.mute{color:#8E8E93}
.btn{position:absolute;display:flex;align-items:center;justify-content:center;background:#0071E3;color:#fff;font-weight:600}
.touch{position:absolute;width:58px;height:58px;margin:-29px 0 0 -29px;border-radius:50%;background:rgba(60,60,67,.22);border:2px solid rgba(60,60,67,.32);opacity:0;z-index:40;pointer-events:none}
"""


def bm_icon(size, r=None):
    """The BioMap app icon: the bird on light grey (same artwork as the 1024 app icon)."""
    return (f'<svg class="icon" width="{size}" height="{size}" viewBox="0 0 48 48" style="box-shadow:0 0 0 1px rgba(0,0,0,.08)">'
            f'<rect width="48" height="48" rx="0" fill="#F5F5F7"/>'
            f'<g transform="translate(3.6 4) scale(.8)" fill="none" stroke="#1D1D1F" stroke-width="3" stroke-linecap="round" stroke-linejoin="round">'
            f'<path d="{build.BIRD_PATH}"/><circle cx="33.5" cy="14.5" r="2" fill="#1D1D1F" stroke="none"/></g></svg>')


def tf_icon(size):
    """A generic blue 'beta testing' app icon (a paper plane), drawn for this ad."""
    return (f'<svg class="icon" width="{size}" height="{size}" viewBox="0 0 48 48"><rect width="48" height="48" fill="#1A8CFF"/>'
            f'<path d="M10 23.5 38 11 30.5 37.5 23.5 28.5 18 33 18.8 25.6Z" fill="#fff"/><path d="M38 11 23.5 28.5" stroke="#1A8CFF" stroke-width="1.6" fill="none"/></svg>')


def generic_icon(size, color):
    return f'<div class="icon" style="width:{size}px;height:{size}px;background:{color}"></div>'


def status(dark=True):
    return ('<div class="status"><div class="time">9:41</div>'
            '<div class="sig"><i style="height:5px"></i><i style="height:7px"></i><i style="height:9px"></i><i style="height:11px"></i></div>'
            '<div class="bat"><i></i></div></div>')


def ring(id_, cx, cy, r=15):
    c = 2 * 3.14159 * r
    return (f'<svg id="{id_}" class="abs" style="left:{cx - r - 3}px;top:{cy - r - 3}px;opacity:0" width="{2 * r + 6}" height="{2 * r + 6}" viewBox="0 0 {2 * r + 6} {2 * r + 6}">'
            f'<circle cx="{r + 3}" cy="{r + 3}" r="{r}" fill="none" stroke="#D1D1D6" stroke-width="3"/>'
            f'<circle class="arc" cx="{r + 3}" cy="{r + 3}" r="{r}" fill="none" stroke="#0071E3" stroke-width="3" stroke-linecap="round" '
            f'stroke-dasharray="{c:.1f}" stroke-dashoffset="{c:.1f}" transform="rotate(-90 {r + 3} {r + 3})" data-c="{c:.1f}"/></svg>')


def screens():
    # 1 - App Store page for TestFlight
    s1 = ('<div class="scr" id="s1">' + status() +
          f'<div class="abs" style="left:24px;top:112px">{tf_icon(100)}</div>'
          '<div class="abs bold" style="left:140px;top:118px;font-size:27px">TestFlight</div>'
          '<div class="abs mute" style="left:140px;top:154px;font-size:15px">Beta testing for iOS apps</div>'
          '<div class="btn" id="b1" style="left:140px;top:186px;width:84px;height:32px;border-radius:16px;font-size:15px">GET</div>' + ring('r1', 182, 202) +
          '<div class="abs" style="left:24px;right:24px;top:262px;height:1px;background:#E5E5EA"></div>'
          '<div class="abs bold" style="left:24px;top:282px;font-size:22px">Preview</div>' +
          ''.join(f'<div class="abs gray" style="left:{24 + i * 122}px;top:326px;width:112px;height:244px;border-radius:18px"></div>' for i in range(3)) + '</div>')
    # 2 - Safari on the invite page
    s2 = ('<div class="scr" id="s2">' + status() +
          f'<div class="abs" style="left:141px;top:176px">{bm_icon(120)}</div>'
          '<div class="abs bold" style="left:0;right:0;top:322px;text-align:center;font-size:29px">Join the BioMap beta</div>'
          '<div class="abs mute" style="left:60px;right:60px;top:368px;text-align:center;font-size:16px;line-height:1.35">To test this beta, you need TestFlight on your iPhone.</div>'
          '<div class="btn" id="b2" style="left:61px;top:430px;width:280px;height:50px;border-radius:25px;font-size:18px">View in TestFlight</div>'
          '<div class="abs gray" style="left:24px;right:24px;top:770px;height:52px;border-radius:26px;display:flex;align-items:center;justify-content:center;font-size:16px;color:#3A3A3C">'
          f'<span class="mute" style="margin-right:6px">&#128274;</span>{LINK_SHORT.split("/")[0]}</div></div>')
    # 3 - the TestFlight app
    s3 = ('<div class="scr gray" id="s3">' + status() +
          '<div class="abs bold" style="left:0;right:0;top:66px;text-align:center;font-size:17px">BioMap</div>'
          f'<div class="abs" style="left:151px;top:150px">{bm_icon(100)}</div>'
          '<div class="abs bold" style="left:0;right:0;top:272px;text-align:center;font-size:30px">BioMap</div>'
          '<div class="abs mute" style="left:0;right:0;top:314px;text-align:center;font-size:16px">Version 1.0 (2)</div>'
          '<div class="abs" id="s3msg" style="left:44px;right:44px;top:372px;text-align:center;font-size:17px;line-height:1.4;color:#3A3A3C">You&rsquo;re invited to test BioMap.</div>'
          '<div class="btn" id="b3" style="left:61px;top:535px;width:280px;height:50px;border-radius:25px;font-size:19px">Accept</div>' + ring('r3', 201, 560) +
          '<div class="abs mute" style="left:0;right:0;top:612px;text-align:center;font-size:13px">Beta &middot; Expires in 90 days</div></div>')
    # 4 - home screen
    cols = ['#C9D6EA', '#E8D5C4', '#CFE3D4', '#E4CFE0', '#D9D9DE', '#F0E3B8', '#C4DDE3', '#E8C9C9']
    grid = ''
    k = 0
    for row in range(5):
        for col in range(4):
            x = 30 + col * 93.3
            y = 100 + row * 106
            if (row, col) == (1, 2):
                grid += (f'<div class="abs" id="home-bm" style="left:{x}px;top:{y}px;width:62px;text-align:center">{bm_icon(62)}'
                         f'<div style="font-size:11px;margin-top:5px;color:#1D1D1F;white-space:nowrap;margin-left:-6px;margin-right:-6px"><span style="display:inline-block;width:6px;height:6px;border-radius:50%;background:#FF9500;margin-right:4px"></span>BioMap</div></div>')
            elif (row, col) == (0, 0):
                grid += f'<div class="abs" style="left:{x}px;top:{y}px;width:62px;text-align:center">{tf_icon(62)}<div style="font-size:11px;margin-top:5px;margin-left:-6px;margin-right:-6px">TestFlight</div></div>'
            else:
                grid += (f'<div class="abs" style="left:{x}px;top:{y}px;width:62px">{generic_icon(62, cols[k % len(cols)])}'
                         f'<div style="height:6px;width:36px;margin:9px auto 0;border-radius:3px;background:rgba(60,60,67,.28)"></div></div>')
                k += 1
    dock = ''.join(f'<div class="abs" style="left:{37 + i * 82}px;top:778px">{generic_icon(60, cols[(i + 3) % len(cols)])}</div>' for i in range(4))
    s4 = ('<div class="scr" id="s4" style="background:#E5E7EE">' + status() + grid +
          '<div class="abs" style="left:18px;right:18px;top:764px;height:88px;border-radius:30px;background:rgba(255,255,255,.55)"></div>' + dock + '</div>')
    # 5 - BioMap launching (the bird-to-microbe loader)
    s5 = ('<div class="scr" id="s5">' + status() +
          '<svg class="abs" style="left:101px;top:276px;overflow:visible" width="200" height="200" viewBox="0 0 200 200">'
          '<path id="ldpath" d="" fill="none" stroke="#0071E3" stroke-width="3.4" stroke-linejoin="round"/><circle id="ldnuc" cx="100" cy="100" r="9" fill="#0071E3" opacity="0"/></svg>'
          '<div class="abs" id="ldname" style="left:0;right:0;top:508px;text-align:center;font-size:16px;font-weight:600;color:#6E6E73">Bird</div></div>')
    return s1 + s2 + s3 + s4 + s5


JS = r"""
const $=id=>document.getElementById(id);
const ORG=__ORG__, TAPS=__TAPS__, SC=__SC__, T_IN=__TIN__, T_OUT=__TOUT__;
const lerp=(a,b,x)=>a+(b-a)*x;
const win=(t,a,b)=>ease(seg(t,a,.4))*(1-ease(seg(t,b,.4)));
const kick=(t,at,d)=>clamp(1-Math.abs(t-(at+d/2))/(d/2),0,1);
function contour(r,S,R){const n=r.length,c=S/2,P=r.map((v,i)=>{const a=2*Math.PI*i/n;return[c+v*R*Math.cos(a),c-v*R*Math.sin(a)]});
  let d='M'+P[0][0].toFixed(2)+' '+P[0][1].toFixed(2);
  for(let i=0;i<n;i++){const p0=P[(i-1+n)%n],p1=P[i],p2=P[(i+1)%n],p3=P[(i+2)%n];
    d+='C'+(p1[0]+(p2[0]-p0[0])/6).toFixed(2)+' '+(p1[1]+(p2[1]-p0[1])/6).toFixed(2)+' '+(p2[0]-(p3[0]-p1[0])/6).toFixed(2)+' '+(p2[1]-(p3[1]-p1[1])/6).toFixed(2)+' '+p2[0].toFixed(2)+' '+p2[1].toFixed(2)}
  return d+'Z'}
function ringAt(id,t,a,b){const el=$(id),arc=el.querySelector('.arc'),c=+arc.dataset.c;const p=seg(t,a,b-a);arc.style.strokeDashoffset=c*(1-p);el.style.opacity=(t>=a&&t<b)?1:0}
function press(el,t,at){el.style.transform='scale('+(1-.06*kick(t,at,.3))+')'}
window.custom=function(t){
  const phone=$('phone');
  const pin=ease(seg(t,T_IN,.9)), pout=ease(seg(t,T_OUT,.7));
  phone.style.transform='translateY('+((1-pin)*1700+pout*1700)+'px) scale(1.3)';
  for(const k in SC){$(k).style.opacity=win(t,SC[k][0],SC[k][1])}
  // 1: GET -> ring -> OPEN
  const b1=$('b1');
  b1.textContent=t<7.1?'GET':'OPEN';
  b1.style.opacity=(t<5.8||t>=7.1)?1:0; press(b1,t,5.7);
  ringAt('r1',t,5.85,7.1);
  // 2: tap "View in TestFlight"
  press($('b2'),t,11.3);
  // 3: Accept -> Install -> ring -> Open
  const b3=$('b3');
  b3.textContent=t<15.6?'Accept':(t<19.0?'Install':'Open');
  b3.style.opacity=(t>=17.4&&t<19.0)?0:1; press(b3,t,t<16.5?15.3:17.3);
  $('s3msg').textContent=t<15.6?'You’re invited to test BioMap.':'Ready to install.';
  ringAt('r3',t,17.5,19.0);
  // 4: BioMap icon opens
  press($('home-bm'),t,20.9);
  const op=ease(seg(t,21.0,.9));
  $('s5').style.transform='scale('+lerp(.82,1,op)+')';
  // 5: bird -> microbe loader
  const lt=Math.max(0,t-21.95), cyc=1.1+.95, step=Math.floor(lt/cyc), within=lt-step*cyc, n=ORG.length;
  const from=ORG[step%n], to=ORG[(step+1)%n], raw=within<1.1?0:(within-1.1)/.95, e=raw<.5?4*raw*raw*raw:1-Math.pow(-2*raw+2,3)/2;
  const rr=from.r.map((v,i)=>v+(to.r[i]-v)*e);
  $('ldpath').setAttribute('d',contour(rr,200,84));
  const na=(step%n)>=5?1:0, nb=((step+1)%n)>=5?1:0; $('ldnuc').setAttribute('opacity',na+(nb-na)*e);
  $('ldname').textContent=(e>.5?to:from).name;
  // touch indicator
  const touch=$('touch'); let vis=0, px=0, py=0;
  for(const [T,x,y] of TAPS){
    if(t>=T-.6&&t<T+.5){
      const u=ease(seg(t,T-.6,.6));
      px=lerp(x+60,x,u); py=lerp(y+130,y,u);
      vis=clamp((t-(T-.6))/.2)*(1-clamp((t-(T+.2))/.3));
      touch.style.transform='scale('+(1-.22*kick(t,T,.3))+')';
    }
  }
  touch.style.left=px+'px'; touch.style.top=py+'px'; touch.style.opacity=vis;
};
"""


def page(final=False):
    # captions: [eyebrow, headline, sub]
    caps = [('Step 1 of 4', 'Install TestFlight.', 'It&rsquo;s Apple&rsquo;s free app for trying betas.'),
            ('Step 2 of 4', 'Open the invite link.', 'On your iPhone, tap the BioMap beta link.'),
            ('Step 3 of 4', 'Accept. Then install.', 'Tap Accept, then Install.'),
            ('Step 4 of 4', 'Open BioMap.', 'The orange dot means it&rsquo;s a beta.')]
    body = ''
    # intro (in the joined ad the rename story just showed the bird, so this is text only)
    if not final:
        body += ('<div class="abs" data-a=".1" data-b="3.1" data-y="0" style="left:0;right:0;top:420px;display:flex;justify-content:center">'
                 + build.bird(300, draw=True, color='#1D1D1F', sw=2.1).replace('class="draw"', 'class="draw" data-a=".2" data-d="1.4"') + '</div>')
    body += (f'<div class="abs" style="left:100px;right:100px;top:{640 if final else 800}px" data-a=".7" data-b="3.1" data-d=".9">'
             '<div class="eyebrow">The public beta is open</div><h1 style="margin-top:20px">BioMap is on TestFlight.</h1>'
             '<div class="sub">Here&rsquo;s how to get in, in four taps.</div></div>')
    for (a, b), (eb, h, sub) in zip(STEPS, caps):
        body += f'<div class="cap" data-a="{a}" data-b="{b}" data-d=".7" data-y="30"><div class="eyebrow">{eb}</div><h2>{h}</h2><div class="sub" style="margin-top:14px">{sub}</div></div>'
    body += f'<div id="phone"><div id="screen"><div class="island"></div>{screens()}<div class="touch" id="touch"></div></div></div>'
    # call to action
    body += ('<div class="abs" style="left:100px;right:100px;top:380px" data-a="23.9" data-d=".8">'
             '<div class="eyebrow">Join the public beta</div><h1 style="margin-top:18px">Get BioMap on your iPhone.</h1>'
             '<div class="sub">Open this link on your iPhone.</div>'
             f'<span class="linkpill" style="font-size:41px;padding:34px 48px">{LINK_SHORT}</span></div>')
    body += ('<div class="abs" style="left:100px;right:100px;top:1150px" data-a="25.2" data-d=".8">'
             '<div style="font-size:36px;line-height:1.45;color:#6E6E73">iPhone with iOS 17 or later.<br>Found a bug? In the app, open Profile and tap Report a bug.</div></div>')
    body += ('<div class="abs" style="left:100px;right:100px;top:1480px;display:flex;align-items:center;gap:18px;font-size:40px;font-weight:700;letter-spacing:-.02em" data-a="25.6" data-d=".6" data-y="0">'
             + build.bird(60, color='#1D1D1F', sw=2.4) + 'BioMap</div>')
    js = (JS.replace('__ORG__', json.dumps(ORGANISMS)).replace('__TAPS__', json.dumps(TAPS)).replace('__SC__', json.dumps(SCENES))
          .replace('__TIN__', str(T_IN)).replace('__TOUT__', str(T_OUT)))
    return (f'<!doctype html><html><head><meta charset="utf-8"><style>{CSS}</style></head><body>{body}'
            f'<script>{build.TL_JS}{js}</script></body></html>')


def render(mp4, final=False, cover=None):
    from playwright.sync_api import sync_playwright
    mp4 = pathlib.Path(mp4)
    mp4.parent.mkdir(parents=True, exist_ok=True)
    with sync_playwright() as p:
        b = p.chromium.launch(channel='chrome')
        pg = b.new_page(viewport={'width': 1080, 'height': 1920})
        build.render_reel(pg, NAME, page(final), DUR, mp4)
        audio.add_audio(mp4)      # keyed by file stem, so the file must be called testflight-is-live.mp4
        if cover:
            pg.set_viewport_size({'width': 1080, 'height': 1920})
            pg.goto((build.SRC / f'reel-{NAME}.html').as_uri()); pg.evaluate('document.fonts.ready'); pg.wait_for_timeout(200)
            pg.evaluate('render(26.2)')   # cover = the call to action
            pg.screenshot(path=str(cover), type='png')
        b.close()


def main():
    OUT.mkdir(exist_ok=True)
    render(OUT / f'{NAME}.mp4', cover=OUT / f'{NAME}-cover.png')


if __name__ == '__main__':
    main()
