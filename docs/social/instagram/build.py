"""Builds the Instagram assets (Reels, carousels, stories, profile art) for BioMap.

Every asset is an HTML page whose look at time t is a pure function (window.render(t)), so frames are
deterministic. Playwright (system Chrome) screenshots each frame; ffmpeg encodes the Reels.

  python3 build.py            # everything
  python3 build.py reels      # or: carousels | stories | profile
  python3 build.py genz       # the Gen Z-style beat-synced reels (05-08)
  python3 build.py rebrand    # the name-change announcement reel -> rebrand/
  python3 build.py audio      # re-mux the synthesized soundtrack into the existing reels (no re-render)
Needs: pip install playwright, ffmpeg, Google Chrome.
"""
import pathlib, shutil, subprocess, sys, tempfile
import audio
import genz

HERE = pathlib.Path(__file__).parent
SRC = HERE / 'src'
FPS = 30

BIRD_PATH = "M6 27C11 14 21 7 34 7c2.7 0 5 .4 7 1.1-1.8 1-3.3 2.3-4.4 4C40 12.4 43 13.4 45 15.3c-3 .3-5.6 1.4-7.7 3.2 1 6.7-1.2 13-6.4 17.6C25.8 41.4 18.8 43.6 11 42.4c3.6-1 6.6-2.9 8.8-5.5-5-.4-9.4-3-12.2-7.1 2.6.7 5.1.6 7.4-.4C11 27.8 7.9 25 6 21.2"
def bird(size, cls='', draw=False, color='#1B1812', sw=2.1):
    p = f'<path d="{BIRD_PATH}" {"pathLength=\"1\" class=\"draw\"" if draw else ""}/>'
    return (f'<svg class="{cls}" viewBox="0 0 48 48" width="{size}" height="{size}" fill="none" stroke="{color}" '
            f'stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round">{p}<circle class="eye" cx="33.5" cy="14.5" r="1.4" fill="{color}" stroke="none"/></svg>')

BASE_CSS = """
@font-face{font-family:G;src:url(fonts/geist-latin-wght-normal.woff2);font-weight:100 900}
@font-face{font-family:F;src:url(fonts/fraunces-latin-standard-normal.woff2);font-weight:100 900}
@font-face{font-family:F;font-style:italic;src:url(fonts/fraunces-latin-wght-italic.woff2);font-weight:100 900}
:root{--paper:#F4F1E9;--ink:#211D16;--soft:#6B6255;--clay:#C1602E;--rule:rgba(33,29,22,.14)}
*{box-sizing:border-box;margin:0;padding:0}
html,body{width:100%;height:100%;background:var(--paper);color:var(--ink);font-family:G,sans-serif;overflow:hidden}
.frame{position:absolute;inset:36px;border:3px solid var(--rule)}
.safe{position:absolute;left:100px;right:100px;display:flex;flex-direction:column;justify-content:center}
.eb{font-size:34px;letter-spacing:.14em;text-transform:uppercase;color:var(--clay);margin-bottom:34px}
h1{font-family:F,serif;font-weight:500;font-size:118px;line-height:1.06;letter-spacing:-.012em}
h1 em,h2 em{color:var(--clay);font-style:italic}
h2{font-family:F,serif;font-weight:500;font-size:96px;line-height:1.1}
.num{font-family:F,serif;font-style:italic;font-size:210px;line-height:1;color:var(--clay);font-weight:400}
.sub{font-size:48px;line-height:1.42;color:var(--soft);margin-top:34px}
.pill{display:inline-block;margin-top:52px;padding:26px 44px;border:3px solid var(--ink);font-size:38px;letter-spacing:.01em}
.brandbar{position:absolute;left:100px;right:100px;display:flex;align-items:center;justify-content:space-between;font-size:30px;color:var(--soft)}
.brand{display:flex;align-items:center;gap:14px;font-family:F,serif;font-style:italic;font-size:42px;color:var(--ink)}
.abs{position:absolute}
.draw{stroke-dasharray:1;stroke-dashoffset:1}
[data-a]{opacity:0}
"""

TL_JS = """
const ease=t=>1-Math.pow(1-t,3);
const clamp=x=>Math.min(1,Math.max(0,x));
const seg=(t,a,d)=>clamp((t-a)/d);
window.seg=seg;window.ease=ease;
window.render=function(t){
  document.querySelectorAll('[data-a]').forEach(el=>{
    const a=+el.dataset.a,b=el.dataset.b?+el.dataset.b:Infinity;
    const inn=ease(seg(t,a,+(el.dataset.d||.6))),out=ease(seg(t,b,.4));
    const y=(1-inn)*(+(el.dataset.y||44))-out*24;
    el.style.opacity=inn*(1-out);
    el.style.transform=`translateY(${y}px)`;
  });
  document.querySelectorAll('.draw').forEach(p=>{
    const a=+p.dataset.a||0,d=+p.dataset.d||1.4;
    const prog=ease(seg(t,a,d));
    p.style.strokeDashoffset=1-prog;
    const eye=p.closest('svg').querySelector('.eye');
    if(eye)eye.style.opacity=clamp((prog-.85)/.15);
  });
  if(window.custom)window.custom(t);
};
"""

def page(body, js='', css=''):
    return f'<!doctype html><html><head><meta charset="utf-8"><style>{BASE_CSS}{css}</style></head><body><div class="frame"></div>{body}<script>{TL_JS}{js}</script></body></html>'

def brandbar(top, a=None):
    da = f' data-a="{a}" data-d="0.5" data-y="0"' if a is not None else ''
    return f'<div class="brandbar" style="top:{top}px"{da}><div class="brand">{bird(52)}BioMap</div><div>getbiomap.web.app</div></div>'

def safe(inner, top=300, bottom=420, a=None, b=None, extra=''):
    at = f' data-a="{a}"' + (f' data-b="{b}"' if b is not None else '') if a is not None else ''
    return f'<div class="safe" style="top:{top}px;bottom:{bottom}px;{extra}"{at}>{inner}</div>'

# ------------------------------------------------------------------ REELS
def reel_how():
    dur = 16.6
    body = ''
    body += f'<div class="abs" data-a=".1" data-b="3.3" data-y="0" style="left:0;right:0;top:330px;display:flex;justify-content:center">{bird(430, draw=True).replace("class=\"draw\"", "class=\"draw\" data-a=\".2\" data-d=\"1.6\"")}</div>'
    body += safe('<div class="eb" data-a=".3" data-b="3.3">Citizen science</div><h1 data-a=".9" data-b="3.3" data-d="0.9">Every bird you see becomes <em>data that matters.</em></h1>', top=790, bottom=420, extra='justify-content:flex-start')
    for n, (num, title, sub, a, b) in enumerate([
        ('1', 'Capture', 'A photo, or up to 30 seconds of a call.', 3.5, 7.0),
        ('2', 'Identified on your phone', 'No upload needed for a suggestion.', 7.2, 10.7),
        ('3', 'Community confirms', 'Others confirm, correct, or mark it unsure.', 10.9, 14.0)]):
        body += safe(f'<div class="num">{num}</div><h2 style="margin-top:8px">{title}</h2><div class="sub">{sub}</div>', a=a, b=b)
    body += safe('<div class="eb">Try it</div><h1>See it on the <em>live map.</em></h1><div class="sub">In your browser now. iOS app coming soon.</div><div><span class="pill">Link in bio</span></div>', a=14.2)
    body += brandbar(1450, a=0.4)
    return page(body), dur

def waveform_js(n, y0, h, a, b):
    return f"""
const bars=[];const wrap=document.getElementById('wave');
for(let i=0;i<{n};i++){{const d=document.createElement('div');d.style.cssText='width:14px;background:#C1602E;border-radius:7px;position:absolute;bottom:0;left:'+(i*(880/{n}))+'px';wrap.appendChild(d);bars.push(d)}}
window.custom=function(t){{
  const vis=ease(seg(t,{a},.6))*(1-ease(seg(t,{b},.5)));
  wrap.style.opacity=vis;
  bars.forEach((d,i)=>{{const k=.22+.78*Math.abs(Math.sin(t*3.1+i*.55)*Math.cos(t*1.7+i*.31));d.style.height=({h}*k)+'px'}});
}};"""

def reel_tips():
    dur = 15.0
    body = safe('<div class="eb" data-a=".1" data-b="3.0">Tips: bird sound</div><h1 data-a=".5" data-b="3.0" data-d=".9">Record a bird call <em>your phone can identify.</em></h1>', a=None, top=300, bottom=420)
    for num, txt, a, b in [('1', 'Get close and <em>hold still.</em>', 3.2, 6.4), ('2', 'Keep wind and <em>voices out.</em>', 6.6, 9.8), ('3', 'Short and clean <em>beats long and noisy.</em>', 10.0, 13.0)]:
        body += safe(f'<div class="num">{num}</div><h1 style="margin-top:6px;font-size:104px">{txt}</h1>', top=300, bottom=650, a=a, b=b)
    body += '<div id="wave" class="abs" style="left:100px;top:1130px;width:880px;height:260px;opacity:0"></div>'
    body += safe('<div class="eb">BioMap</div><h1>Identify birds by <em>sound.</em></h1><div class="sub">On your phone. iOS app coming soon.</div><div><span class="pill">Link in bio</span></div>', a=13.2)
    body += brandbar(1450, a=0.4)
    return page(body, js=waveform_js(40, 1130, 260, 3.0, 13.0)), dur

def reel_ondevice():
    dur = 14.0
    phone = '<svg viewBox="0 0 200 380" width="380" height="722" fill="none" stroke="#211D16" stroke-width="3" stroke-linecap="round"><rect x="6" y="6" width="188" height="368" rx="30" pathLength="1" class="draw" data-a="3.3" data-d="1.4"/><line x1="78" y1="22" x2="122" y2="22"/></svg>'
    cloud = '<svg viewBox="0 0 120 90" width="420" height="315" fill="none" stroke="#211D16" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><path d="M30 72a20 20 0 0 1 3-40 28 28 0 0 1 55 6 18 18 0 0 1 2 34z"/><line class="draw" data-a="7.9" data-d=".7" pathLength="1" x1="14" y1="84" x2="106" y2="8" stroke="#C1602E" stroke-width="5"/></svg>'
    body = safe('<div class="eb" data-a=".1" data-b="3.0">On-device</div><h1 data-a=".5" data-b="3.0" data-d=".9">Where does your bird photo <em>go?</em></h1>', top=300, bottom=420)
    body += f'<div class="abs" data-a="3.2" data-b="7.0" data-y="0" style="left:0;right:0;top:300px;display:flex;justify-content:center;flex-direction:column;align-items:center"><div style="position:relative;width:380px;height:722px">{phone}<div id="ring" style="position:absolute;left:190px;top:361px;width:10px;height:10px;margin:-5px;border:4px solid #C1602E;border-radius:50%;opacity:0"></div><div style="position:absolute;left:0;right:0;top:300px;display:flex;justify-content:center">{bird(120)}</div></div></div>'
    body += safe('<h2 style="text-align:center;font-size:74px" data-a="4.0" data-b="7.0">Identified right here, <em>on your phone.</em></h2>', top=1050, bottom=420, a=None)
    body += f'<div class="abs" data-a="7.2" data-b="10.3" data-y="0" style="left:0;right:0;top:360px;display:flex;justify-content:center">{cloud}</div>'
    body += safe('<h2 style="text-align:center" data-a="7.4" data-b="10.3">Nothing is uploaded <em>just to get a suggestion.</em></h2>', top=900, bottom=420)
    body += safe('<div class="eb">BioMap</div><h1>You decide what <em>to share.</em></h1><div class="sub">iOS app coming soon. Link in bio.</div>', a=10.5)
    body += brandbar(1450, a=0.4)
    js = "window.custom=function(t){const r=document.getElementById('ring');const p=((t-4)%1.6)/1.6;const on=t>4&&t<7;r.style.opacity=on?(1-p)*.9:0;const s=10+p*520;r.style.width=s+'px';r.style.height=s+'px';r.style.margin=(-s/2)+'px'}"
    return page(body, js=js), dur

def reel_unsure():
    dur = 12.4
    bar = ('<div style="position:relative;width:880px;height:44px;border:3px solid #211D16;border-radius:26px"><div id="fill" style="position:absolute;left:0;top:0;bottom:0;width:0;background:#C1602E;border-radius:22px"></div>'
           '<div style="position:absolute;left:60%;top:-30px;bottom:-30px;width:4px;background:#211D16"></div></div>'
           '<div style="position:relative;width:880px;height:46px;font-size:30px;color:#6B6255;margin-top:34px"><span style="position:absolute;left:0">confidence</span><span style="position:absolute;left:60%;transform:translateX(-50%)">enough to suggest</span></div>')
    body = safe('<h1 data-a=".2" data-b="2.9" data-d=".9">A wrong answer is worse than <em>no answer.</em></h1>', top=300, bottom=420)
    body += safe('<h1 data-a="3.1" data-b="5.3" data-d=".9">BioMap <em>doesn\'t guess.</em></h1>', top=300, bottom=420)
    body += safe(f'<div class="eb">Illustration: a low-confidence photo</div>{bar}<h2 style="margin-top:70px;font-size:84px">Below the bar? <em>It says so.</em></h2><div style="margin-top:44px"><span class="pill" style="margin-top:0">Marked unsure</span></div>', a=5.5, b=9.3, top=300, bottom=420)
    body += safe('<h1>Then other birders <em>can help.</em></h1><div class="sub">Confirm it, correct it, or mark it unsure. iOS app coming soon.</div><div><span class="pill">Link in bio</span></div>', a=9.5)
    body += brandbar(1450, a=0.4)
    js = "window.custom=function(t){document.getElementById('fill').style.width=(ease(seg(t,6.0,1.6))*34)+'%'}"
    return page(body, js=js), dur

def pin(size=90, badge=None):
    p = f'<svg viewBox="0 0 24 32" width="{size}" height="{size*32/24:.0f}" fill="none" stroke="#211D16" stroke-width="2" stroke-linejoin="round"><path pathLength="1" class="draw" data-a="3.4" data-d="1.1" d="M12 1C6.5 1 2 5.6 2 11c0 7 10 19 10 19s10-12 10-19c0-5.4-4.5-10-10-10z"/><circle cx="12" cy="11" r="4" fill="#211D16" stroke="none"/></svg>'
    b = f'<div id="badge" class="abs" style="left:{size*.66:.0f}px;top:-10px;width:54px;height:54px;border-radius:50%;background:#C1602E;color:#F4F1E9;display:flex;align-items:center;justify-content:center;font-size:30px;font-family:G,sans-serif;font-weight:600;opacity:0">1</div>' if badge else ''
    return f'<div class="abs" style="position:relative">{p}{b}</div>'

def reel_map():
    dur = 13.6
    body = safe('<div class="eb" data-a=".1" data-b="3.2">The map</div><h1 data-a=".5" data-b="3.2" data-d=".9">Ten sightings, same tree? <em>One pin.</em></h1>', top=300, bottom=420)
    body += f'<div class="abs" data-a="3.4" data-b="6.8" data-y="0" style="left:0;right:0;top:520px;display:flex;justify-content:center">{pin(160, badge=True)}</div>'
    body += safe('<h2 style="text-align:center;font-size:78px" data-a="4.6" data-b="6.8">A number means <em>more than one.</em></h2>', top=1000, bottom=420, a=None)
    bar = '<div style="width:880px;height:96px;border:3px solid #211D16;border-radius:48px;display:flex;align-items:center;padding:0 40px;gap:20px"><svg viewBox="0 0 24 24" width="34" height="34" fill="none" stroke="#211D16" stroke-width="3"><circle cx="10" cy="10" r="7"/><line x1="15" y1="15" x2="21" y2="21"/></svg><span id="q" style="font-size:40px;color:#211D16"></span></div>'
    body += safe(f'<div class="eb">Search</div>{bar}<div class="sub" style="margin-top:44px">Species, notes, or usernames.</div>', a=7.0, b=10.2, top=300, bottom=420)
    body += safe('<div class="eb">BioMap</div><h1>See every sighting, <em>mapped.</em></h1><div class="sub">Bookmark the ones you want to find again. Link in bio.</div><div><span class="pill">Link in bio</span></div>', a=10.4)
    body += brandbar(1450, a=0.4)
    js = """window.custom=function(t){
  const badge=document.getElementById('badge'); if(badge){badge.style.opacity=ease(seg(t,4.0,0.5)); badge.textContent=t<5.3?'2':t<6.4?'5':'9'}
  const q=document.getElementById('q'); if(q){const word='sparrow';const n=Math.floor(clamp((t-7.6)/0.9,0,1)*word.length);q.textContent=word.slice(0,n)+(t>7.6&&t<9.0&&n<word.length?'|':'')}
};"""
    return page(body, js=js), dur

def reel_offline():
    dur = 13.0
    nosig = '<svg viewBox="0 0 64 48" width="140" height="105" fill="none" stroke="#211D16" stroke-width="3" stroke-linecap="round"><rect x="18" y="8" width="28" height="40" rx="6"/><path d="M26 6 L38 42 M38 6 L26 42" stroke="#C1602E" stroke-width="4"/></svg>'
    queue = ''.join(f'<div class="abs" style="left:{i*40}px;top:{-i*10}px;width:180px;height:110px;background:#F4F1E9;border:3px solid #211D16;border-radius:14px"></div>' for i in range(3))
    cloud = '<svg viewBox="0 0 120 90" width="300" height="225" fill="none" stroke="#211D16" stroke-width="3" stroke-linejoin="round"><path d="M30 72a20 20 0 0 1 3-40 28 28 0 0 1 55 6 18 18 0 0 1 2 34z"/></svg>'
    check = '<svg viewBox="0 0 24 24" width="60" height="60" fill="none" stroke="#C1602E" stroke-width="4" stroke-linecap="round" stroke-linejoin="round"><path pathLength="1" class="draw" data-a="8.6" data-d=".6" d="M4 13 L10 19 L20 6"/></svg>'
    body = safe('<h1 data-a=".2" data-b="3.0" data-d=".9">No signal doesn\'t mean <em>no sighting.</em></h1>', top=300, bottom=420)
    body += f'<div class="abs" data-a="3.2" data-b="6.4" data-y="0" style="left:0;right:0;top:560px;display:flex;justify-content:center">{nosig}</div>'
    body += safe('<h2 style="text-align:center;font-size:76px" data-a="3.6" data-b="6.4">It saves right where <em>you are.</em></h2>', top=980, bottom=420, a=None)
    body += f'<div class="abs" data-a="6.6" data-b="9.8" data-y="0" style="left:0;right:0;top:520px;display:flex;justify-content:center;align-items:center;gap:60px"><div style="position:relative;width:260px;height:130px">{queue}</div><div style="position:relative">{cloud}<div style="position:absolute;left:30px;top:15px">{check}</div></div></div>'
    body += safe('<h2 style="text-align:center;font-size:72px" data-a="7.2" data-b="9.8">And sends the moment <em>you\'re back.</em></h2>', top=980, bottom=420, a=None)
    body += safe('<div class="eb">BioMap</div><h1>Nothing gets lost in a <em>dead zone.</em></h1><div class="sub">iOS app coming soon. Link in bio.</div><div><span class="pill">Link in bio</span></div>', a=10.0)
    body += brandbar(1450, a=0.4)
    return page(body), dur

REELS = {'01-how-biomap-works': reel_how, '02-tips-bird-sound': reel_tips, '03-stays-on-your-phone': reel_ondevice, '04-says-when-unsure': reel_unsure,
         '09-the-map': reel_map, '10-works-offline': reel_offline}

# ------------------------------------------------------------------ TRAILER (mock cursor opens "BioMap.mp4", then a recap montage)
CURSOR_SVG = '<svg viewBox="0 0 24 24" width="34" height="34" style="filter:drop-shadow(0 2px 3px rgba(0,0,0,.35))"><path d="M4 2 L4 20 L9 15.4 L12.2 22 L15.3 20.6 L12.1 14 L19 14 Z" fill="#111" stroke="#fff" stroke-width="1.2" stroke-linejoin="round"/></svg>'

def file_icon():
    return ('<div style="display:flex;flex-direction:column;align-items:center;gap:16px">'
            '<svg viewBox="0 0 64 48" width="96" height="72" fill="none" stroke="#211D16" stroke-width="3" stroke-linejoin="round">'
            '<rect x="2" y="2" width="60" height="44" rx="8"/><path d="M26 15 L26 33 L43 24 Z" fill="#C1602E" stroke="none"/></svg>'
            '<div style="font-size:28px;color:#211D16;font-family:G,sans-serif">BioMap.mp4</div></div>')

def reel_trailer():
    dur = 19.6
    desktop = (f'<div id="desktop" class="abs" style="inset:0">'
               f'<div id="win" class="abs" style="left:190px;top:560px;width:700px;height:460px;background:#fff;border:3px solid #211D16;border-radius:18px;box-shadow:0 30px 70px rgba(0,0,0,.2)"></div>'
               f'<div class="abs" style="left:190px;top:560px;width:700px;height:64px;border-bottom:2px solid rgba(33,29,22,.14);display:flex;align-items:center;padding:0 26px;font-size:26px;color:#6B6255;font-family:G,sans-serif">Downloads</div>'
               f'<div id="icon" class="abs" style="left:440px;top:672px;width:200px;transform-origin:center">{file_icon()}</div>'
               f'<div id="cur" class="abs" style="left:0;top:0">{CURSOR_SVG}</div></div>')
    openrect = '<div id="openrect" class="abs" style="inset:0;background:#211D16;transform-origin:540px 747px;transform:scale(0.001);opacity:0"></div>'
    # recap montage: one beat lifted from each existing reel, compressed
    video = safe('<div class="eb" data-a="3.5" data-b="5.9">BioMap, <em>in brief</em></div>', top=300, bottom=420, a=None)
    video += f'<div class="abs" data-a="3.7" data-b="5.9" data-y="0" style="left:0;right:0;top:900px;display:flex;justify-content:center">{bird(340, draw=True).replace("class=\"draw\"", "class=\"draw\" data-a=\"3.8\" data-d=\"1.3\"")}</div>'
    video += safe('<h1 data-a="6.0" data-b="8.2" data-d=".7">Every bird you see becomes <em>data that matters.</em></h1>', top=300, bottom=420)
    video += safe('<h1 data-a="8.4" data-b="10.6" data-d=".7">Identify birds <em>by sound.</em></h1>', top=300, bottom=420)
    video += safe('<h1 data-a="10.8" data-b="13.0" data-d=".7">Identified right here, <em>on your phone.</em></h1>', top=300, bottom=420)
    video += safe('<h1 data-a="13.2" data-b="15.4" data-d=".7">BioMap <em>doesn\'t guess.</em></h1>', top=300, bottom=420)
    video += safe('<h1 data-a="15.6" data-b="17.6" data-d=".7">One pin per place. <em>Works with no signal.</em></h1>', top=300, bottom=420)
    video += safe('<div class="eb">BioMap</div><h1>See it for <em>yourself.</em></h1><div class="sub">iOS app coming soon. Link in bio.</div><div><span class="pill">Link in bio</span></div>', a=17.8)
    video += brandbar(1450, a=18.2)
    body = desktop + openrect + f'<div id="video" class="abs" style="inset:0;opacity:0">{video}</div>'
    js = """
function pulse(t,at,d){return 1+0.07*clamp(1-Math.abs(t-(at+d/2))/(d/2),0,1)}
window.custom=function(t){
  const p0={x:900,y:1500}, p1={x:540,y:747};
  const cp=ease(seg(t,0.2,2.0));
  const cx=p0.x+(p1.x-p0.x)*cp, cy=p0.y+(p1.y-p0.y)*cp-Math.sin(cp*Math.PI)*90;
  document.getElementById('cur').style.transform=`translate(${cx}px,${cy}px)`;
  const icon=document.getElementById('icon');
  const s=Math.max(pulse(t,2.35,.2),pulse(t,2.65,.2));
  icon.style.transform=`scale(${s})`;
  const desktop=document.getElementById('desktop');
  desktop.style.opacity=1-ease(seg(t,3.0,0.4));
  const or_=document.getElementById('openrect');
  const grow=ease(seg(t,2.85,0.55));
  or_.style.transform=`scale(${Math.max(0.001,grow*1.3)})`;
  or_.style.opacity=Math.min(1,grow*3)*(1-ease(seg(t,3.65,0.35)));
  document.getElementById('video').style.opacity=ease(seg(t,3.55,0.6));
};"""
    return page(body, js=js), dur

def cap(inner, a, b, top=330):
    """A caption block in the safe area above the scene."""
    return safe(inner, top=top, bottom=1920 - top - 330, a=a, b=b, extra='justify-content:flex-start')

LOGO_CX, LOGO_CY, LOGO_SIZE = 540, 800, 420
FORM_A, FORM_D = 26.2, 2.6

SHOWCASE_JS = r"""
const $=id=>document.getElementById(id);
const NS='http://www.w3.org/2000/svg', INK='#211D16', CLAY='#C1602E';
const BIRD230=__B230__, BIRD70=__B70__, BIRD_D='__BIRD_PATH__';
const FORM_A=__FORM_A__, FORM_D=__FORM_D__, LCX=__LCX__, LCY=__LCY__, LSZ=__LSZ__;
function rngf(s){return function(){s|=0;s=s+0x6D2B79F5|0;let t=Math.imul(s^s>>>15,1|s);t=t+Math.imul(t^t>>>7,61|t)^t;return((t^t>>>14)>>>0)/4294967296}}
const R=rngf(11);
function S(tag,at,par){const e=document.createElementNS(NS,tag);for(const k in at)e.setAttribute(k,at[k]);if(par)par.appendChild(e);return e}
const W=$('world');
function D(css,par,html){const d=document.createElement('div');d.style.cssText='position:absolute;'+css;if(html!==undefined)d.innerHTML=html;(par||W).appendChild(d);return d}
const vis=(t,a,b,fi,fo)=>ease(seg(t,a,fi||.6))*(1-ease(seg(t,b,fo||.6)));
const back=x=>{const c1=1.70158,c3=c1+1;return 1+c3*Math.pow(x-1,3)+c1*Math.pow(x-1,2)};
const kick=(t,at,d)=>clamp(1-Math.abs(t-(at+d/2))/(d/2),0,1);
const upd=[];

/* ---------- sun, clouds, hills, trees ---------- */
const sun=D('left:330px;top:0;width:420px;height:420px;opacity:0',W,'<svg viewBox="-210 -210 420 420" width="420" height="420"><g id="rays" stroke="'+CLAY+'" stroke-width="4" stroke-linecap="round"></g><circle r="120" fill="'+CLAY+'"/></svg>');
const rays=sun.querySelector('#rays');
for(let i=0;i<20;i++){const a=i/20*Math.PI*2,r=i%2?185:208;S('line',{x1:Math.cos(a)*150,y1:Math.sin(a)*150,x2:Math.cos(a)*r,y2:Math.sin(a)*r},rays)}
upd.push(t=>{const y=1560-600*ease(seg(t,3.4,5.2));sun.style.top=(y-210)+'px';sun.style.opacity=.95*vis(t,3.4,12.2,.9,1.3);rays.setAttribute('transform','rotate('+(t*9)+')');sun.style.transform='scale('+(1+.03*Math.sin(t*1.6))+')'});

const CLOUD='<svg viewBox="0 0 120 90" width="100%" height="100%" fill="none" stroke="'+INK+'" stroke-width="2.5" stroke-linejoin="round"><path d="M30 72a20 20 0 0 1 3-40 28 28 0 0 1 55 6 18 18 0 0 1 2 34z"/></svg>';
const clouds=[[100,640,300,26],[600,760,220,18],[850,590,340,32]].map(c=>({d:D('width:'+c[2]+'px;height:'+c[2]*.75+'px;opacity:0;top:'+c[1]+'px',W,CLOUD),x0:c[0],v:c[3]}));
upd.push(t=>clouds.forEach(c=>{c.d.style.left=(((c.x0+t*c.v)%1500)-300)+'px';c.d.style.opacity=.5*vis(t,3.6,13.2,1,1)}));

const hills=S('svg',{viewBox:'0 0 1080 1920',width:1080,height:1920,fill:'none',stroke:INK,'stroke-width':3},null);
hills.style.cssText='position:absolute;left:0;top:0;opacity:0';W.appendChild(hills);
const hillA=S('path',{d:'M-10 1350 C160 1290 300 1370 480 1330 S820 1290 1090 1350',pathLength:1,opacity:.3},hills);
const hillB=S('path',{d:'M-10 1780 C200 1720 380 1800 560 1760 S900 1730 1090 1790',pathLength:1},hills);
hillA.style.strokeDasharray=1;hillB.style.strokeDasharray=1;
upd.push(t=>{hills.style.opacity=vis(t,3.4,20.4,.5,.9);hillA.style.strokeDashoffset=1-ease(seg(t,3.4,1.4));hillB.style.strokeDashoffset=1-ease(seg(t,3.6,1.4))});

const TREE='<svg viewBox="0 0 60 120" width="100%" height="100%" fill="none" stroke="'+INK+'" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><line x1="30" y1="70" x2="30" y2="118"/><path d="M30 8C14 8 6 24 10 38 2 42 2 58 12 62 8 74 18 86 32 82 46 88 56 74 50 62 60 58 60 42 50 38 54 24 46 8 30 8Z"/></svg>';
const trees=[];
function tree(x,base,sc,op,i){const w=90*sc,h=180*sc;trees.push({d:D('left:'+x+'px;top:'+(base-h)+'px;width:'+w+'px;height:'+h+'px;opacity:0;transform-origin:50% 100%',W,TREE),op:op,ph:R()*6,amp:1+R()*1.4,i:i})}
for(let i=0;i<10;i++)tree(-30+i*118+R()*30,1340,.62+R()*.2,.22,i);
[[-70,1800,1.9],[120,1850,1.45],[830,1810,1.85],[985,1860,1.4],[420,1900,1.1]].forEach((a,i)=>tree(a[0],a[1],a[2],.9,10+i));
upd.push(t=>trees.forEach(o=>{const k=ease(seg(t,3.3+o.i*.06,.9))*(1-ease(seg(t,20.0+o.i*.03,.8)));o.d.style.opacity=o.op*k;o.d.style.transform='rotate('+(Math.sin(t*.9+o.ph)*o.amp)+'deg) scale(1,'+(.8+.2*k)+')'}));

/* ---------- drifting life: leaves, fireflies, flying birds ---------- */
const LEAF='<svg viewBox="0 0 24 24" width="100%" height="100%" fill="none" stroke="'+INK+'" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 20C4 9 11 4 20 4c0 9-5 16-16 16z"/><path d="M4 20L14 10"/></svg>';
const leaves=[];for(let i=0;i<18;i++)leaves.push({d:D('width:26px;height:26px;opacity:0',W,LEAF),x0:R()*1080,y0:R()*2000,v:55+R()*70,ph:R()*6,s:(R()<.5?-1:1)*(50+R()*60)});
upd.push(t=>leaves.forEach(l=>{const y=((l.y0+t*l.v)%2060)-70;l.d.style.transform='translate('+(l.x0+Math.sin(t*1.3+l.ph)*46)+'px,'+y+'px) rotate('+(t*l.s+l.ph*40)+'deg)';l.d.style.opacity=.55*vis(t,4.2,12.8,1,1)}));
const flies=[];for(let i=0;i<24;i++)flies.push({d:D('width:8px;height:8px;border-radius:50%;background:'+CLAY+';box-shadow:0 0 16px 4px rgba(193,96,46,.45);opacity:0',W),x:80+R()*920,y:900+R()*760,ph:R()*6,sp:1.2+R()*2});
upd.push(t=>flies.forEach(f=>{const tw=Math.pow(.5+.5*Math.sin(t*f.sp+f.ph),2);f.d.style.transform='translate('+(f.x+Math.sin(t*.7+f.ph)*30)+'px,'+(f.y+Math.cos(t*.9+f.ph)*24)+'px)';f.d.style.opacity=tw*vis(t,4.6,12.6,1,1)}));
const flyers=[];for(let i=0;i<6;i++)flyers.push({d:D('width:70px;height:70px;opacity:0',W,BIRD70),t0:3.6+i*.6,v:170+R()*90,y0:640+R()*300,ph:R()*6});
upd.push(t=>flyers.forEach(f=>{const x=-120+(t-f.t0)*f.v,y=f.y0+Math.sin((t-f.t0)*1.6)*36-(t-f.t0)*10;const fl=.72+.28*Math.abs(Math.sin(t*9+f.ph));f.d.style.transform='translate('+x+'px,'+y+'px) rotate('+(-8+Math.sin(t*2+f.ph)*5)+'deg) scale(1,'+fl+')';f.d.style.opacity=(x>-130&&x<1150&&t>f.t0)?vis(t,f.t0,9.6,.4,.8):0}));

/* ---------- branch, the singer, its song ---------- */
const branch=S('svg',{viewBox:'0 0 1080 300',width:1080,height:300,fill:'none',stroke:INK,'stroke-width':5,'stroke-linecap':'round'},null);
branch.style.cssText='position:absolute;left:0;top:940px;opacity:0';W.appendChild(branch);
const bp=['M1090 118 C900 132 700 92 430 122','M800 104 C780 66 730 54 700 30','M600 106 C590 78 560 66 540 56','M960 122 C950 160 920 176 890 190'].map(d=>{const p=S('path',{d:d,pathLength:1},branch);p.style.strokeDasharray=1;return p});
const bl=[[700,30],[540,56],[890,190],[735,58]].map(c=>S('path',{d:'M'+c[0]+' '+c[1]+'c-16-4-26-16-28-30 16 0 28 8 28 30z',fill:'none','stroke-width':3},branch));
upd.push(t=>{branch.style.opacity=vis(t,7.4,12.4,.4,.8);bp.forEach((p,i)=>p.style.strokeDashoffset=1-ease(seg(t,7.5+i*.18,.9)));bl.forEach((l,i)=>l.style.opacity=ease(seg(t,8.4+i*.2,.5)))});
const perch=D('width:230px;height:230px;opacity:0',W,BIRD230);
const rings=[0,1,2,3].map(()=>D('border-radius:50%;border:4px solid '+CLAY+';opacity:0',W));
const NOTE='<svg viewBox="0 0 30 40" width="100%" height="100%" fill="none" stroke="'+CLAY+'" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><ellipse cx="9" cy="32" rx="6" ry="4.5" fill="'+CLAY+'"/><path d="M15 31V5l12 7"/></svg>';
const notes=[];for(let i=0;i<7;i++)notes.push(D('width:44px;height:58px;opacity:0',W,NOTE));
let beak={x:0,y:0};
upd.push(t=>{
  const fl=seg(t,7.6,1.1),p=ease(fl);let x=1350+(470-1350)*p,y=260+(852-260)*p-Math.sin(fl*Math.PI)*140,sy=1,rot=0;
  if(fl<1){sy=.7+.3*Math.abs(Math.sin(t*14));rot=-10*(1-fl)}
  else{y+=Math.sin(t*3)*3;rot=Math.sin(t*2.2)*2.5;const sing=vis(t,9.0,12.2,.3,.3);sy=1+.035*Math.sin(t*10)*sing;x+=Math.sin(t*10)*1.2*sing}
  perch.style.transform='translate('+x+'px,'+y+'px) rotate('+rot+'deg) scale(1,'+sy+')';
  perch.style.opacity=t<7.6?0:1-ease(seg(t,12.0,.7));
  beak.x=x+216;beak.y=y+72;
  rings.forEach((r,k)=>{const age=((t-9.0-k*.45)%1.8)/1.8,on=vis(t,9.0,12.2,.2,.5);const s=40+Math.max(0,age)*720;r.style.width=r.style.height=s+'px';r.style.left=(beak.x-s/2)+'px';r.style.top=(beak.y-s/2)+'px';r.style.opacity=t<9.0?0:(1-Math.max(0,age))*.7*on});
  notes.forEach((n,k)=>{const age=((t-9.2-k*.7)%2.8)/2.8,on=vis(t,9.1,12.3,.2,.5);n.style.transform='translate('+(beak.x+age*300+Math.sin(age*9+k)*26)+'px,'+(beak.y-age*440)+'px) rotate('+(Math.sin(age*7+k)*22)+'deg) scale('+(.7+.5*Math.sin(age*Math.PI))+')';n.style.opacity=t<9.1?0:Math.sin(Math.max(0,age)*Math.PI)*on})
});

/* ---------- app mockups: shared phone chrome, tab bar, ad-style chips and taps ---------- */
const PS=1.25, PLEFT=302;
const FRAME='<svg viewBox="0 0 200 380" width="380" height="722" fill="#FBF9F3" stroke="'+INK+'" stroke-width="3" stroke-linecap="round"><rect x="6" y="6" width="188" height="368" rx="30"/><line x1="78" y1="22" x2="122" y2="22"/></svg>';
const TI={map:'<svg viewBox="0 0 24 24" width="32" height="32" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"><path d="M12 2C8 2 5 5 5 9c0 5 7 13 7 13s7-8 7-13c0-4-3-7-7-7z"/><circle cx="12" cy="9" r="2.5"/></svg>',
 mic:'<svg viewBox="0 0 24 24" width="32" height="32" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><rect x="9" y="3" width="6" height="12" rx="3"/><path d="M5 11a7 7 0 0 0 14 0M12 18v3"/></svg>',
 trophy:'<svg viewBox="0 0 24 24" width="32" height="32" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M8 4h8v5a4 4 0 0 1-8 0zM8 6H4v2a3 3 0 0 0 4 3M16 6h4v2a3 3 0 0 1-4 3M12 13v4M8 20h8"/></svg>'};
function mkPhone(title){
  const p=D('left:'+PLEFT+'px;top:2000px;width:380px;height:722px;opacity:0;transform-origin:50% 0',W,FRAME);
  D('left:34px;top:34px;font:600 20px Geist,sans-serif;color:'+INK,p,'6:42');
  D('right:34px;top:36px;width:36px;height:17px;border:2.5px solid '+INK+';border-radius:5px',p,'<i style="position:absolute;left:2px;top:2px;bottom:2px;width:72%;background:'+INK+';border-radius:2px"></i>');
  D('left:0;right:0;top:66px;text-align:center;font:600 28px Fraunces,serif;color:'+INK,p,title);
  return p}
function tabbar(p,active){const b=D('left:16px;right:16px;bottom:16px;height:64px;border-top:2px solid rgba(33,29,22,.14);display:flex;justify-content:space-around;align-items:center',p);const o={};['map','mic','trophy'].forEach(k=>{o[k]=D('position:relative;color:'+(k===active?CLAY:'#8a8375')+';display:flex;flex-direction:column;align-items:center;padding-top:6px',b,TI[k])});return o}
const chips=[];
function chip(txt,x,y,ta,tb,side){const c=D('left:'+x+'px;top:'+y+'px;padding:16px 26px 16px 22px;background:#fff;border:3px solid '+INK+';border-radius:40px;box-shadow:0 14px 34px rgba(33,29,22,.18);font:600 32px Geist,sans-serif;color:'+INK+';white-space:nowrap;display:flex;align-items:center;gap:14px;opacity:0;transform-origin:50% 50%',W,'<span style="width:16px;height:16px;border-radius:50%;background:'+CLAY+'"></span>'+txt);chips.push({c,ta,tb,side:side||1,ph:R()*6})}
upd.push(t=>chips.forEach(o=>{const k=back(seg(t,o.ta,.6)),out=ease(seg(t,o.tb,.5));o.c.style.opacity=t<o.ta?0:Math.min(1,k*2)*(1-out);o.c.style.transform='translate('+(o.side*(1-k)*140)+'px,'+(Math.sin(t*1.8+o.ph)*7)+'px) scale('+(.8+.2*k)+') rotate('+(Math.sin(t*1.1+o.ph)*1.2)+'deg)'}));
const taps=[];
function tap(par,x,y,at){const r=D('width:60px;height:60px;border-radius:50%;background:rgba(193,96,46,.3);border:3px solid '+CLAY+';opacity:0;left:'+(x-30)+'px;top:'+(y-30)+'px',par);taps.push({r,at})}
const tapAll=t=>taps.forEach(o=>{const a=(t-o.at)/.8;o.r.style.opacity=(a>0&&a<1)?Math.sin(a*Math.PI):0;o.r.style.transform='scale('+(.5+Math.max(0,Math.min(1,a))*1.2)+')'});

/* ---------- phone 1: the Sound tab, recording and the suggestion card ---------- */
const phone=mkPhone('Sound'),tabs1=tabbar(phone,'mic');
const rec=D('left:110px;top:108px;width:160px;height:42px;border:3px solid '+INK+';border-radius:22px;display:flex;align-items:center;justify-content:center;gap:10px;font:600 22px Geist,sans-serif;color:'+INK+';opacity:0',phone,'<span id="rdot" style="width:13px;height:13px;border-radius:50%;background:'+CLAY+'"></span><span id="rtxt">REC 0:00</span>');
const bars=[];const barBox=D('left:40px;top:150px;width:300px;height:230px;opacity:0',phone);
for(let i=0;i<24;i++)bars.push(D('width:8px;background:'+CLAY+';border-radius:4px;left:'+(i*12.4+4)+'px;height:20px;transform-origin:50% 100%',barBox));
const rbtn=D('left:135px;top:420px;width:110px;height:110px;opacity:0',phone,'<div id="rring" style="position:absolute;inset:0;border-radius:50%;border:4px solid '+CLAY+'"></div><div id="rcore" style="position:absolute;left:20px;top:20px;width:70px;height:70px;border-radius:50%;background:'+CLAY+'"></div>');
const spin=D('left:120px;top:190px;width:140px;height:140px;opacity:0',phone,'<svg viewBox="0 0 100 100" width="140" height="140" fill="none" stroke-linecap="round"><circle cx="50" cy="50" r="42" stroke="rgba(33,29,22,.14)" stroke-width="6"/><circle id="arc" cx="50" cy="50" r="42" stroke="'+CLAY+'" stroke-width="6" stroke-dasharray="70 200"/></svg>');
const lab=D('left:0;width:380px;top:346px;text-align:center;font:500 24px Geist,sans-serif;color:#6B6255;opacity:0',phone,'Listening on this phone');
const sk='<div class="sk" style="position:absolute;left:22px;top:TOPpx;width:WIDTHpx;height:20px;border-radius:10px;background:rgba(33,29,22,.12);overflow:hidden"><i style="position:absolute;top:0;bottom:0;width:70px;background:linear-gradient(90deg,transparent,rgba(255,255,255,.75),transparent)"></i></div>';
const card=D('left:24px;top:376px;width:332px;height:262px;border:3px solid '+INK+';border-radius:20px;background:#F4F1E9;opacity:0',phone,
 '<div style="position:absolute;left:22px;top:16px;font:600 19px Geist,sans-serif;letter-spacing:.14em;color:'+CLAY+'">SUGGESTION</div>'+sk.replace('TOP',52).replace('WIDTH',220)+sk.replace('TOP',86).replace('WIDTH',150)+
 '<div style="position:absolute;left:22px;top:126px;width:288px;height:20px;border:3px solid '+INK+';border-radius:12px"><div id="cfill" style="position:absolute;left:0;top:0;bottom:0;width:0;background:'+CLAY+';border-radius:8px"></div><div style="position:absolute;left:60%;top:-9px;bottom:-9px;width:3px;background:'+INK+'"></div></div>'+
 '<svg viewBox="0 0 24 24" width="38" height="38" style="position:absolute;right:18px;top:12px" fill="none" stroke="'+CLAY+'" stroke-width="3.5" stroke-linecap="round" stroke-linejoin="round"><path id="chkp" pathLength="1" d="M4 13 L10 19 L20 6" style="stroke-dasharray:1;stroke-dashoffset:1"/></svg>'+
 '<div style="position:absolute;left:22px;top:154px;font:500 19px Geist,sans-serif;color:#6B6255">sure enough to suggest</div>'+
 '<div style="position:absolute;left:18px;right:18px;top:196px;display:flex;gap:10px;font:600 21px Geist,sans-serif"><span id="bright" style="flex:1;text-align:center;padding:10px 0;border:3px solid '+INK+';border-radius:14px;background:'+CLAY+';color:#F4F1E9">Right</span><span style="flex:1;text-align:center;padding:10px 0;border:3px solid '+INK+';border-radius:14px">Wrong</span><span style="flex:1;text-align:center;padding:10px 0;border:3px solid '+INK+';border-radius:14px">Unsure</span></div>');
const sks=[...card.querySelectorAll('.sk i')];
tap(phone,190,475,13.5);tap(card,84,230,19.3);
chip('Identified on-device',20,1330,16.5,19.4,-1);chip('Right / Wrong / Unsure',560,1410,18.4,19.7,1);
upd.push(t=>{
  const inn=back(seg(t,12.3,1.1)),out=ease(seg(t,19.5,.9));
  phone.style.top=(2000-1440*inn+1100*out)+'px';phone.style.opacity=t<12.3?0:1-ease(seg(t,19.9,.5));
  phone.style.transform='rotate('+((1-inn)*-8+Math.sin(t*1.4)*.6)+'deg) scale('+PS+')';
  rec.style.opacity=vis(t,13.5,16.5,.4,.4);
  const secs=Math.floor(10*clamp((t-13.6)/2.8,0,1));$('rtxt').textContent='REC 0:'+(secs<10?'0':'')+secs;$('rdot').style.opacity=.5+.5*Math.sin(t*8);
  const rb=vis(t,13.3,16.6,.3,.4);rbtn.style.opacity=rb;$('rring').style.transform='scale('+(1+.12*Math.sin(t*7))+')';$('rcore').style.transform='scale('+(t<13.6?1:.62)+')';$('rcore').style.borderRadius=t<13.6?'50%':'14px';
  barBox.style.opacity=vis(t,13.6,16.9,.4,.5);
  bars.forEach((b,i)=>{const env=.5+.5*Math.sin(t*2.1),k=Math.abs(Math.sin(t*6+i*.7)*Math.cos(t*2.3+i*.4)),h=10+190*env*k*(1-ease(seg(t,16.4,.5)));b.style.height=h+'px';b.style.top=(115-h/2)+'px'});
  spin.style.opacity=vis(t,16.6,18.0,.4,.4);$('arc').setAttribute('transform','rotate('+(t*300)+' 50 50)');lab.style.opacity=vis(t,16.7,17.9,.4,.4);
  const c=ease(seg(t,17.9,.7));card.style.opacity=c*(1-ease(seg(t,19.6,.5)));card.style.transform='translateY('+((1-c)*60)+'px)';
  $('cfill').style.width=(ease(seg(t,18.3,1.0))*78)+'%';$('chkp').style.strokeDashoffset=1-ease(seg(t,19.0,.5));$('bright').style.transform='scale('+(1+.1*kick(t,19.3,.3))+')';
  sks.forEach((s,i)=>s.style.left=(((t*260+i*90)%420)-110)+'px')
});

/* ---------- phone 2: the Map tab, a search, pins and a confirmation toast ---------- */
const phone2=mkPhone('Map'),tabs2=tabbar(phone2,'map');
const sbar=D('left:22px;top:112px;width:336px;height:48px;border:3px solid '+INK+';border-radius:24px;background:#fff;display:flex;align-items:center;padding:0 16px;gap:10px;font:500 24px Geist,sans-serif;color:'+INK,phone2,'<svg viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="'+INK+'" stroke-width="3"><circle cx="10" cy="10" r="7"/><line x1="15" y1="15" x2="21" y2="21"/></svg><span id="q"></span>');
const MAPBOX=D('left:22px;top:172px;width:336px;height:470px;border:3px solid '+INK+';border-radius:18px;overflow:hidden;background:#FBF9F3',phone2);
const ms=S('svg',{viewBox:'0 0 336 470',width:336,height:470,fill:'none'},null);ms.style.cssText='position:absolute;left:0;top:0';MAPBOX.appendChild(ms);
const lines=[];for(let k=0;k<6;k++){let d='';for(let x=-10;x<=350;x+=20){const y=30+k*80+Math.sin(x*.02+k*1.3)*26+Math.sin(x*.05+k*2.1)*9;d+=(x<0?'M':'L')+x+' '+y+' '}lines.push(S('path',{d:d,pathLength:1,stroke:'rgba(33,29,22,.16)','stroke-width':2},ms))}
const roads=['M-10 380 C70 320 130 400 210 340 S300 270 350 290','M60 -10 C80 120 140 160 150 250 S190 400 220 480','M350 130 C280 160 250 90 190 110 S100 80 30 130'].map(d=>S('path',{d:d,pathLength:1,stroke:'rgba(33,29,22,.34)','stroke-width':4,'stroke-linecap':'round'},ms));
lines.concat(roads).forEach(p=>p.style.strokeDasharray=1);
const PIN='<svg viewBox="0 0 24 32" width="100%" height="100%" fill="'+CLAY+'" stroke="'+INK+'" stroke-width="1.6" stroke-linejoin="round"><path d="M12 1C6.5 1 2 5.6 2 11c0 7 10 19 10 19s10-12 10-19c0-5.4-4.5-10-10-10z"/><circle cx="12" cy="11" r="4" fill="#F4F1E9" stroke="none"/></svg>';
const pins=[[168,240,70,21.0],[70,150,42,21.6],[250,120,42,21.8],[250,330,42,22.0],[100,340,38,22.3],[40,250,34,22.5],[290,230,34,22.7],[170,90,34,22.9],[240,420,30,23.1]].map(p=>({x:p[0],y:p[1],s:p[2],ta:p[3],d:D('left:'+(p[0]-p[2]*.375)+'px;top:'+(p[1]-p[2])+'px;width:'+p[2]*.75+'px;height:'+p[2]+'px;transform-origin:50% 100%;opacity:0',MAPBOX,PIN),r:D('border-radius:50%;border:3px solid '+CLAY+';opacity:0',MAPBOX)}));
const badge=D('left:'+(168+14)+'px;top:'+(240-70-16)+'px;width:44px;height:44px;border-radius:50%;background:'+INK+';color:#F4F1E9;display:flex;align-items:center;justify-content:center;font:600 24px Geist,sans-serif;opacity:0',MAPBOX,'1');
const arcs=[1,2,3].map(j=>{const p=pins[j];const a=S('path',{d:'M168 210 Q'+((168+p.x)/2)+' '+(Math.min(240,p.y)-70)+' '+p.x+' '+(p.y-16),pathLength:1,stroke:CLAY,'stroke-width':3.5,'stroke-linecap':'round','stroke-dasharray':'1'},ms);return a});
const toast=D('left:40px;right:40px;top:98px;padding:14px 18px;background:'+INK+';color:#F4F1E9;border-radius:18px;font:600 21px Geist,sans-serif;display:flex;align-items:center;gap:12px;opacity:0;box-shadow:0 12px 28px rgba(0,0,0,.25)',phone2,'<svg viewBox="0 0 24 24" width="26" height="26" fill="none" stroke="#F4F1E9" stroke-width="3.5" stroke-linecap="round" stroke-linejoin="round"><path d="M4 13 L10 19 L20 6"/></svg><span>Confirmed by 3 birders</span>');
chip('One pin per place',20,1330,21.2,25.0,-1);chip('Community confirms',560,1410,22.6,25.2,1);
upd.push(t=>{
  const inn=back(seg(t,19.8,.9)),out=ease(seg(t,25.4,.9));
  phone2.style.top=(2000-1440*inn)+'px';phone2.style.opacity=t<19.8?0:ease(seg(t,19.8,.4))*(1-out);
  phone2.style.transform='rotate('+((1-inn)*6+Math.sin(t*1.2)*.5)+'deg) scale('+PS+')';
  lines.forEach((p,i)=>p.style.strokeDashoffset=1-ease(seg(t,20.4+i*.08,1.0)));roads.forEach((p,i)=>p.style.strokeDashoffset=1-ease(seg(t,20.6+i*.2,1.1)));
  const q=$('q'),word='sparrow',n=Math.floor(clamp((t-20.3)/.7,0,1)*word.length);q.textContent=word.slice(0,n)+((t>20.3&&t<21.3)?'|':'');
  pins.forEach((p,i)=>{const k=seg(t,p.ta,.55),e=back(k);p.d.style.opacity=k>0?1:0;p.d.style.transform='scale('+e+')';const age=(t-p.ta-.25)/1.0;p.r.style.opacity=(age>0&&age<1)?(1-age)*.8:0;const s=16+Math.max(0,age)*110;p.r.style.width=p.r.style.height=s+'px';p.r.style.left=(p.x-s/2)+'px';p.r.style.top=(p.y-s/2)+'px'});
  badge.style.opacity=ease(seg(t,21.2,.4));badge.textContent=t<21.9?'1':t<22.6?'2':'3';badge.style.transform='scale('+(1+.25*kick(t,21.9,.3)+.25*kick(t,22.6,.3))+')';
  arcs.forEach((a,j)=>a.style.strokeDashoffset=1-ease(seg(t,21.9+j*.35,.7)));
  const tin=ease(seg(t,22.7,.45))*(1-ease(seg(t,24.4,.4)));toast.style.opacity=tin;toast.style.transform='translateY('+((1-ease(seg(t,22.7,.45)))*-40)+'px)'
});
upd.push(tapAll);

/* ---------- the flock: sighting dots on the map become the birds that form the mark ---------- */
const cv=$('logo-cv'),cx2=cv.getContext('2d');
const path=S('path',{d:BIRD_D},null);const plen=path.getTotalLength(),N=260,TG=[],ST=[];
for(let i=0;i<N;i++){const pt=path.getPointAtLength(i/N*plen);TG.push({x:LCX+(pt.x-24)/48*LSZ,y:LCY+(pt.y-24)/48*LSZ})}
for(let i=0;i<N;i++){ST.push({x:345+R()*390,y:720+R()*640,ta:23.3+Math.pow(i/N,1.7)*2.5,ph:R()*6,sz:1.5+R()*1.8})}
const STAR=(x,y,r)=>{cx2.beginPath();for(let k=0;k<8;k++){const a=k*Math.PI/4,rr=k%2?r*.28:r;cx2[k?'lineTo':'moveTo'](x+Math.cos(a)*rr,y+Math.sin(a)*rr)}cx2.closePath();cx2.fill()};
const DONE=FORM_A+.6+FORM_D;
upd.push(t=>{
  if(t<23.2)return;cx2.clearRect(0,0,1080,1920);cx2.fillStyle=INK;
  for(let i=0;i<N;i++){const s=ST[i],g=ease(seg(t,FORM_A+i/N*.6,FORM_D));
    const app=back(seg(t,s.ta,.5));if(app<=0)continue;
    const idle={x:s.x+Math.sin(t*1.7+s.ph)*3,y:s.y+Math.cos(t*1.3+s.ph)*3};
    const x=idle.x+(TG[i].x-idle.x)*g,y=idle.y+(TG[i].y-idle.y)*g;
    const wave=t>DONE?.55+.4*Math.sin(i/N*Math.PI*6-t*2.4):1;
    if(g>0&&g<1){const g2=ease(seg(t-.07,FORM_A+i/N*.6,FORM_D)),x2=idle.x+(TG[i].x-idle.x)*g2,y2=idle.y+(TG[i].y-idle.y)*g2;cx2.strokeStyle=INK;cx2.globalAlpha=.35;cx2.lineWidth=2;cx2.beginPath();cx2.moveTo(x2,y2);cx2.lineTo(x,y);cx2.stroke()}
    cx2.globalAlpha=Math.min(1,.4+.55*g)*wave*Math.min(1,app);cx2.beginPath();cx2.arc(x,y,(s.sz*Math.min(1.3,app))*(1+.4*g),0,7);cx2.fill()}
  if(t>DONE-.1){const age=(t-DONE)/1.3;cx2.fillStyle=CLAY;for(let i=0;i<30;i++){if(age<0||age>1)break;const k=(i*9)%N,a=Math.sin(Math.min(1,Math.max(0,age*1.2-(i%5)*.06))*Math.PI);cx2.globalAlpha=a;STAR(TG[k].x,TG[k].y,16*a)}}
  cx2.globalAlpha=1
});

/* ---------- intro (desktop + cursor) and the transition ---------- */
window.custom=function(t){
  const p0={x:900,y:1500},p1={x:540,y:747};
  const cp=ease(seg(t,.2,2.0)),cxp=p0.x+(p1.x-p0.x)*cp,cyp=p0.y+(p1.y-p0.y)*cp-Math.sin(cp*Math.PI)*90;
  const press=Math.max(kick(t,2.35,.18),kick(t,2.65,.18));
  $('cur').style.transform='translate('+cxp+'px,'+cyp+'px) scale('+(1-.18*press)+')';
  $('icon').style.transform='scale('+(1+.08*press)+')';$('icon').style.background='rgba(193,96,46,'+(.12*ease(seg(t,1.9,.3)))+')';
  [2.35,2.65].forEach((a,i)=>{const age=(t-a)/.7,r=$('rp'+i);r.style.opacity=(age>0&&age<1)?(1-age)*.7:0;const s=30+Math.max(0,age)*220;r.style.width=r.style.height=s+'px';r.style.left=(540-s/2)+'px';r.style.top=(747-s/2)+'px'});
  $('prog').style.width=(ease(seg(t,2.4,.5))*100)+'%';$('proglabel').style.opacity=ease(seg(t,2.35,.2))*(1-ease(seg(t,2.9,.2)));
  $('desktop').style.opacity=1-ease(seg(t,2.9,.3));
  $('swash').style.transform='translateX('+(-1600+ease(seg(t,2.85,.7))*3200)+'px)';
  $('video').style.opacity=ease(seg(t,3.0,.3));
  if(t<3.0)return;
  $('world').style.transform='scale('+(1+.05*seg(t,3.4,9)*(1-seg(t,19.5,1.4)))+')';
  upd.forEach(f=>f(t))
};
"""

def reel_showcase():
    """Reel 12, "A sighting's journey": a different story from reel 11's recap. Same file-open intro and swash wipe,
    then one sighting travels from a forest at dawn (a bird sings) to a phone (recorded, identified on-device)
    to a map (other birders confirm it) and finally the whole flock gathers into the BioMap mark."""
    import json
    dur = 32.8
    desktop = (f'<div id="desktop" class="abs" style="inset:0">'
               f'<div id="win" class="abs" style="left:190px;top:560px;width:700px;height:460px;background:#fff;border:3px solid #211D16;border-radius:18px;box-shadow:0 30px 70px rgba(0,0,0,.2)"></div>'
               f'<div class="abs" style="left:190px;top:560px;width:700px;height:64px;border-bottom:2px solid rgba(33,29,22,.14);display:flex;align-items:center;padding:0 26px;font-size:26px;color:#6B6255;font-family:G,sans-serif">Downloads</div>'
               f'<div id="icon" class="abs" style="left:440px;top:672px;width:200px;transform-origin:center;border-radius:14px;padding-bottom:6px">{file_icon()}</div>'
               f'<div id="proglabel" class="abs" style="left:190px;width:700px;top:930px;text-align:center;font-size:24px;color:#6B6255;font-family:G,sans-serif;opacity:0">Opening BioMap.mp4</div>'
               f'<div class="abs" style="left:290px;top:972px;width:500px;height:8px;border-radius:4px;background:rgba(33,29,22,.12);overflow:hidden"><div id="prog" style="height:100%;width:0;background:#C1602E"></div></div>'
               f'<div id="rp0" class="abs" style="border-radius:50%;border:4px solid #C1602E;opacity:0"></div><div id="rp1" class="abs" style="border-radius:50%;border:4px solid #C1602E;opacity:0"></div>'
               f'<div id="cur" class="abs" style="left:0;top:0">{CURSOR_SVG}</div></div>')
    swash_path = 'M0 60 C120 -30 260 130 400 40 C560 -50 700 110 860 30 C1020 -40 1180 100 1400 40 L1400 2160 C1180 2100 1020 2240 860 2170 C700 2250 560 2090 400 2160 C260 2250 120 2090 0 2160 Z'
    swash = f'<svg id="swash" class="abs" style="left:-160px;top:-140px" viewBox="0 0 1400 2200" width="1400" height="2200" fill="#211D16"><path d="{swash_path}"/></svg>'
    h = 'font-size:92px'
    caps = ''
    caps += cap(f'<div class="eb">6:42 a.m.</div><h1 style="{h}" data-d=".9">Somewhere in <em>a forest.</em></h1>', 3.8, 7.5)
    caps += cap(f'<h1 style="{h}">A bird starts <em>singing.</em></h1><div class="sub" style="font-size:44px">One you\'ve never heard before.</div>', 7.9, 12.0)
    caps += cap(f'<div class="eb">Illustration</div><h1 style="{h}">Hold still. <em>Ten seconds.</em></h1>', 12.6, 16.1)
    caps += cap(f'<h1 style="{h}">It listens <em>right on your phone.</em></h1>', 16.3, 17.9)
    caps += cap(f'<h1 style="font-size:78px">Sure enough? <em>It suggests.</em><br>Not sure? <em>It says so.</em></h1>', 18.0, 19.7)
    caps += cap(f'<h1 style="{h}">Nearby birders <em>confirm it.</em></h1>', 20.2, 23.0)
    caps += cap(f'<h1 style="{h}">One sighting. <em>Thousands together.</em></h1>', 23.3, 26.0)
    gather = '<canvas id="logo-cv" class="abs" style="inset:0" width="1080" height="1920"></canvas>'
    word_a = FORM_A + 0.6 + FORM_D - 0.2
    letters = ''.join(f'<span data-a="{word_a + i * .09:.2f}" data-y="70" data-d=".7" style="display:inline-block">{c}</span>' for i, c in enumerate('Bio'))
    letters += '<em>' + ''.join(f'<span data-a="{word_a + (3 + i) * .09:.2f}" data-y="70" data-d=".7" style="display:inline-block">{c}</span>' for i, c in enumerate('Map')) + '</em>'
    end = safe(f'<h1 style="text-align:center;font-size:150px">{letters}</h1>', top=1090, bottom=400)
    end += safe('<div class="sub" style="text-align:center">iOS app coming soon. Link in bio.</div><div style="display:flex;justify-content:center"><span class="pill">Link in bio</span></div>', a=word_a + 1.2, top=1340, bottom=170)
    end += brandbar(1780, a=word_a + 1.6)
    body = desktop + swash + f'<div id="video" class="abs" style="inset:0;opacity:0"><div id="world" class="abs" style="inset:0;transform-origin:50% 60%"></div>{gather}{caps}{end}</div>'
    js = (SHOWCASE_JS.replace('__B230__', json.dumps(bird(230))).replace('__B70__', json.dumps(bird(70))).replace('__BIRD_PATH__', BIRD_PATH)
          .replace('__FORM_A__', str(FORM_A)).replace('__FORM_D__', str(FORM_D)).replace('__LCX__', str(LOGO_CX)).replace('__LCY__', str(LOGO_CY)).replace('__LSZ__', str(LOGO_SIZE)))
    return page(body, js=js), dur

TRAILER = {'11-see-it-in-action': reel_trailer, '12-birds-in-the-wild': reel_showcase}

# ------------------------------------------------------------------ REBRAND (BirdMap -> BioMap announcement; outputs go to rebrand/)
def reel_rebrand():
    """A quiet name-change announcement in the calm house style. Claims nothing about the app beyond the
    name: same app, same community, same sightings. The old name is struck through, the new one writes in."""
    dur = 17.4
    body = safe('<div class="eb" data-a=".2" data-b="3.4">A small announcement</div><h1 data-a=".6" data-b="3.4" data-d=".9">We\u2019re changing <em>our name.</em></h1>', top=300, bottom=420)
    # the old name, struck through, then the new one
    strike = ('<svg height="40" viewBox="0 0 920 40" preserveAspectRatio="none" fill="none" stroke="#C1602E" stroke-width="7" stroke-linecap="round" style="position:absolute;left:-24px;width:calc(100% + 48px);top:92px;overflow:visible">'
              '<path pathLength="1" class="draw" data-a="4.1" data-d=".7" vector-effect="non-scaling-stroke" d="M10 22 C230 8 520 34 910 16"/></svg>')
    body += (f'<div class="abs" data-a="3.6" data-b="7.2" data-y="0" style="left:0;right:0;top:700px;display:flex;flex-direction:column;align-items:center">'
             f'<div style="position:relative;font-family:F,serif;font-style:italic;font-size:200px;line-height:1;color:#6B6255;letter-spacing:-.02em">BirdMap{strike}</div></div>')
    body += ('<div class="abs" data-a="5.0" data-b="7.2" data-y="40" data-d=".9" style="left:0;right:0;top:960px;text-align:center;'
             'font-family:F,serif;font-style:italic;font-size:260px;line-height:1;color:#211D16;letter-spacing:-.03em">Bio<span style="color:#C1602E">Map</span></div>')
    body += safe('<h1 data-a="7.4" data-b="10.6" data-d=".8"><em>Bio:</em> life.<br><em>Map:</em> where it\u2019s found.</h1>', top=300, bottom=420)
    body += safe('<h1 data-a="10.8" data-b="13.6" data-d=".8">Same community.<br>Same sightings.<br><em>New name.</em></h1>', top=300, bottom=420)
    body += safe('<div class="eb">BioMap</div><h1>Say hello to <em>BioMap.</em></h1><div class="sub">iOS app coming soon. Link in bio.</div><div><span class="pill">Link in bio</span></div>', a=13.8)
    body += brandbar(1450, a=0.4)
    return page(body), dur

REBRAND = {'our-new-name': reel_rebrand}

# ------------------------------------------------------------------ CAROUSELS (1080x1350)
def slide_cover(title, eyebrow, hint=True, n=1, total=1):
    body = safe(f'<div class="eb">{eyebrow}</div><h1 style="font-size:116px">{title}</h1>' + ('<div class="sub" style="margin-top:60px">Swipe &rarr;</div>' if hint else ''), top=120, bottom=200)
    return page(body + brandbar(1230)), (1080, 1350)

def slide_point(num, title, sub, n, total):
    body = safe(f'<div class="num">{num}</div><h2 style="margin-top:6px">{title}</h2><div class="sub">{sub}</div>', top=120, bottom=200)
    body += f'<div class="abs" style="right:100px;top:100px;font-size:30px;color:#6B6255">{n}/{total}</div>'
    return page(body + brandbar(1230)), (1080, 1350)

def slide_cta(n, total):
    body = safe('<div class="eb">BioMap</div><h1>See it on the <em>live map.</em></h1><div class="sub">In your browser now. iOS app coming soon.</div><div><span class="pill">Link in bio</span></div>', top=120, bottom=200)
    body += f'<div class="abs" style="right:100px;top:100px;font-size:30px;color:#6B6255">{n}/{total}</div>'
    return page(body + brandbar(1230)), (1080, 1350)

def carousel(slides):
    total = len(slides)
    out = []
    for i, s in enumerate(slides, 1):
        kind = s[0]
        if kind == 'cover': out.append(slide_cover(s[1], s[2], True, i, total))
        elif kind == 'point': out.append(slide_point(s[1], s[2], s[3], i, total))
        else: out.append(slide_cta(i, total))
    return out

CAROUSELS = {
 '01-how-biomap-works': [('cover', 'How BioMap <em>works</em>', 'Citizen science for bird lovers'),
    ('point', '1', 'Capture', 'A photo, or up to 30 seconds of a call.'),
    ('point', '2', 'Identified on your phone', 'A model on your phone suggests the species. Nothing is uploaded just to get a suggestion.'),
    ('point', '3', 'Community confirms', 'Other birders confirm the ID, correct it, or mark it unsure.'),
    ('point', '4', 'It shows on a shared map', 'One pin per place, so you can see what people are finding nearby.'),
    ('cta',)],
 '02-tips-for-better-bird-ids': [('cover', '6 tips for <em>better bird IDs</em>', 'Photos and sound'),
    ('point', '1', 'Photo: make the bird the subject', 'Sharp and well lit beats big and blurry.'),
    ('point', '2', 'Photo: show the whole bird', 'Head, breast and wings all help.'),
    ('point', '3', 'Photo: take a few frames', 'Keep the best one for the best suggestion.'),
    ('point', '4', 'Sound: get close, hold still', 'Distance and movement both make calls harder to hear.'),
    ('point', '5', 'Sound: keep wind and voices out', 'Background noise is what confuses sound models most.'),
    ('point', '6', 'Sound: short and clean wins', 'A clean 10 seconds beats a noisy 30.'),
    ('cta',)],
 '03-what-is-citizen-science': [('cover', 'What is <em>citizen science?</em>', 'And why your sightings count'),
    ('point', '1', 'A sighting is a small fact', 'A species, a place and a time.'),
    ('point', '2', 'Thousands together show a pattern', 'Migration timing, population shifts and range changes.'),
    ('point', '3', 'It only works if it is trustworthy', 'A wrong ID is worse than no record.'),
    ('point', '4', 'So every sighting can be checked', 'Other people confirm or correct the species, and several opinions form a consensus.'),
    ('cta',)],
}

# ------------------------------------------------------------------ STORIES + PROFILE
def story(eyebrow, question, note):
    body = safe(f'<div class="eb">{eyebrow}</div><h1 style="font-size:124px">{question}</h1>', top=280, bottom=820)
    return page(body + brandbar(1420)), (1080, 1920)

STORIES = {
 '01-hardest-bird-by-ear': story('Question', "What's the hardest bird you've tried to <em>ID by ear?</em>", 'Add a Question sticker here'),
 '02-photo-or-sound': story('Poll', 'Stuck on a bird. <em>Photo</em> or <em>sound</em> first?', 'Add a Poll sticker here: Photo / Sound'),
 '03-trust-an-id': story('Question', 'What would make you <em>trust</em> a bird ID?', 'Add a Question sticker here'),
}

def profile_pic(bg, fg):
    body = f'<div class="abs" style="left:0;right:0;top:0;bottom:0;display:flex;align-items:center;justify-content:center;padding-bottom:18px">{bird(830, color=fg, sw=3.3)}</div>'
    return page(body.replace('<div class="frame"></div>', ''), css=f'html,body{{background:{bg}}}.frame{{display:none}}'), (1080, 1080)

def highlight(label):
    body = f'<div class="abs" style="left:0;right:0;top:0;bottom:0;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:60px">{bird(380)}<div style="font-family:F,serif;font-style:italic;font-size:110px">{label}</div></div>'
    return page(body), (1080, 1920)

PROFILE = {'profile-picture': profile_pic('#C1602E', '#F4F1E9'), 'profile-picture-paper': profile_pic('#F4F1E9', '#1B1812'), 'profile-picture-ink': profile_pic('#211D16', '#F4F1E9'), 'highlight-how-it-works': highlight('How it works'), 'highlight-tips': highlight('Tips'), 'highlight-faq': highlight('FAQ'), 'highlight-sightings': highlight('Sightings')}

# ------------------------------------------------------------------ RENDER
def write_html(name, html):
    p = SRC / f'{name}.html'
    p.write_text(html)
    return p.as_uri()

def render_still(pg, name, html, size, out):
    pg.set_viewport_size({'width': size[0], 'height': size[1]})
    pg.goto(write_html(name, html)); pg.evaluate('document.fonts.ready'); pg.wait_for_timeout(150)
    pg.evaluate('render(999)')
    pg.screenshot(path=str(out), type='png')

def render_reel(pg, name, html, dur, out):
    pg.set_viewport_size({'width': 1080, 'height': 1920})
    pg.goto(write_html('reel-' + name, html)); pg.evaluate('document.fonts.ready'); pg.wait_for_timeout(200)
    tmp = pathlib.Path(tempfile.mkdtemp())
    n = int(dur * FPS)
    for i in range(n):
        pg.evaluate(f'render({i / FPS})')
        pg.screenshot(path=str(tmp / f'{i:05d}.jpg'), type='jpeg', quality=94)
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-framerate', str(FPS), '-i', str(tmp / '%05d.jpg'),
                    '-vf', 'scale=in_range=pc:out_range=tv:out_color_matrix=bt709,format=yuv420p',
                    '-c:v', 'libx264', '-preset', 'slow', '-crf', '18', '-profile:v', 'high',
                    '-colorspace', 'bt709', '-color_primaries', 'bt709', '-color_trc', 'bt709', '-color_range', 'tv',
                    '-movflags', '+faststart', str(out)], check=True)
    shutil.rmtree(tmp)
    print('reel', out.name, f'{dur}s', f'{out.stat().st_size/1e6:.1f} MB')

def main(which, filt=None):
    if which == 'audio':
        for f in sorted((HERE / 'reels').glob('*.mp4')): audio.add_audio(f)
        return
    from playwright.sync_api import sync_playwright
    with sync_playwright() as p:
        b = p.chromium.launch(channel='chrome')
        pg = b.new_page(viewport={'width': 1080, 'height': 1920})
        if which in ('all', 'reels'):
            for name, fn in REELS.items():
                if filt and filt not in name: continue
                html, dur = fn(); render_reel(pg, name, html, dur, HERE / 'reels' / f'{name}.mp4')
                audio.add_audio(HERE / 'reels' / f'{name}.mp4')
        if which in ('all', 'trailer'):
            for name, fn in TRAILER.items():
                if filt and filt not in name: continue
                html, dur = fn(); render_reel(pg, name, html, dur, HERE / 'reels' / f'{name}.mp4')
                audio.add_audio(HERE / 'reels' / f'{name}.mp4')
        if which in ('all', 'rebrand'):
            (HERE / 'rebrand').mkdir(exist_ok=True)
            for name, fn in REBRAND.items():
                if filt and filt not in name: continue
                html, dur = fn(); render_reel(pg, name, html, dur, HERE / 'rebrand' / f'{name}.mp4')
                audio.add_audio(HERE / 'rebrand' / f'{name}.mp4')
                pg.set_viewport_size({'width': 1080, 'height': 1920}); pg.goto((SRC / f'reel-{name}.html').as_uri()); pg.evaluate('document.fonts.ready'); pg.wait_for_timeout(200)
                pg.evaluate('render(6.4)'); pg.screenshot(path=str(HERE / 'rebrand' / f'{name}-cover.png'), type='png')   # cover = the name reveal
        if which in ('all', 'genz'):
            for name, fn in genz.REELS.items():
                html, dur = fn(); render_reel(pg, name, html, dur, HERE / 'reels' / f'{name}.mp4')
                audio.add_audio(HERE / 'reels' / f'{name}.mp4')
        if which in ('all', 'carousels'):
            for cname, slides in CAROUSELS.items():
                d = HERE / 'carousels' / cname; d.mkdir(exist_ok=True)
                for i, (html, size) in enumerate(carousel(slides), 1):
                    render_still(pg, f'car-{cname}-{i}', html, size, d / f'{i:02d}.png')
                print('carousel', cname, len(slides), 'slides')
        if which in ('all', 'stories'):
            for name, (html, size) in STORIES.items():
                render_still(pg, 'story-' + name, html, size, HERE / 'stories' / f'{name}.png')
            print('stories', len(STORIES))
        if which in ('all', 'profile'):
            for name, (html, size) in PROFILE.items():
                render_still(pg, 'profile-' + name, html, size, HERE / 'profile' / f'{name}.png')
            print('profile', len(PROFILE))
        b.close()

if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else 'all', sys.argv[2] if len(sys.argv) > 2 else None)
