"""Builds the Instagram assets (Reels, carousels, stories, profile art) for BirdMap.

Every asset is an HTML page whose look at time t is a pure function (window.render(t)), so frames are
deterministic. Playwright (system Chrome) screenshots each frame; ffmpeg encodes the Reels.

  python3 build.py            # everything
  python3 build.py reels      # or: carousels | stories | profile
  python3 build.py genz       # the Gen Z-style beat-synced reels (05-08)
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
    return f'<div class="brandbar" style="top:{top}px"{da}><div class="brand">{bird(52)}BirdMap</div><div>birdmap-citizenscience.web.app</div></div>'

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
    body += safe('<div class="eb">BirdMap</div><h1>Identify birds by <em>sound.</em></h1><div class="sub">On your phone. iOS app coming soon.</div><div><span class="pill">Link in bio</span></div>', a=13.2)
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
    body += safe('<div class="eb">BirdMap</div><h1>You decide what <em>to share.</em></h1><div class="sub">iOS app coming soon. Link in bio.</div>', a=10.5)
    body += brandbar(1450, a=0.4)
    js = "window.custom=function(t){const r=document.getElementById('ring');const p=((t-4)%1.6)/1.6;const on=t>4&&t<7;r.style.opacity=on?(1-p)*.9:0;const s=10+p*520;r.style.width=s+'px';r.style.height=s+'px';r.style.margin=(-s/2)+'px'}"
    return page(body, js=js), dur

def reel_unsure():
    dur = 12.4
    bar = ('<div style="position:relative;width:880px;height:44px;border:3px solid #211D16;border-radius:26px"><div id="fill" style="position:absolute;left:0;top:0;bottom:0;width:0;background:#C1602E;border-radius:22px"></div>'
           '<div style="position:absolute;left:60%;top:-30px;bottom:-30px;width:4px;background:#211D16"></div></div>'
           '<div style="position:relative;width:880px;height:46px;font-size:30px;color:#6B6255;margin-top:34px"><span style="position:absolute;left:0">confidence</span><span style="position:absolute;left:60%;transform:translateX(-50%)">enough to suggest</span></div>')
    body = safe('<h1 data-a=".2" data-b="2.9" data-d=".9">A wrong answer is worse than <em>no answer.</em></h1>', top=300, bottom=420)
    body += safe('<h1 data-a="3.1" data-b="5.3" data-d=".9">BirdMap <em>doesn\'t guess.</em></h1>', top=300, bottom=420)
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
    body += safe('<div class="eb">BirdMap</div><h1>See every sighting, <em>mapped.</em></h1><div class="sub">Bookmark the ones you want to find again. Link in bio.</div><div><span class="pill">Link in bio</span></div>', a=10.4)
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
    body += safe('<div class="eb">BirdMap</div><h1>Nothing gets lost in a <em>dead zone.</em></h1><div class="sub">iOS app coming soon. Link in bio.</div><div><span class="pill">Link in bio</span></div>', a=10.0)
    body += brandbar(1450, a=0.4)
    return page(body), dur

REELS = {'01-how-birdmap-works': reel_how, '02-tips-bird-sound': reel_tips, '03-stays-on-your-phone': reel_ondevice, '04-says-when-unsure': reel_unsure,
         '09-the-map': reel_map, '10-works-offline': reel_offline}

# ------------------------------------------------------------------ TRAILER (mock cursor opens "BirdMap.mp4", then a recap montage)
CURSOR_SVG = '<svg viewBox="0 0 24 24" width="34" height="34" style="filter:drop-shadow(0 2px 3px rgba(0,0,0,.35))"><path d="M4 2 L4 20 L9 15.4 L12.2 22 L15.3 20.6 L12.1 14 L19 14 Z" fill="#111" stroke="#fff" stroke-width="1.2" stroke-linejoin="round"/></svg>'

def file_icon():
    return ('<div style="display:flex;flex-direction:column;align-items:center;gap:16px">'
            '<svg viewBox="0 0 64 48" width="96" height="72" fill="none" stroke="#211D16" stroke-width="3" stroke-linejoin="round">'
            '<rect x="2" y="2" width="60" height="44" rx="8"/><path d="M26 15 L26 33 L43 24 Z" fill="#C1602E" stroke="none"/></svg>'
            '<div style="font-size:28px;color:#211D16;font-family:G,sans-serif">BirdMap.mp4</div></div>')

def reel_trailer():
    dur = 19.6
    desktop = (f'<div id="desktop" class="abs" style="inset:0">'
               f'<div id="win" class="abs" style="left:190px;top:560px;width:700px;height:460px;background:#fff;border:3px solid #211D16;border-radius:18px;box-shadow:0 30px 70px rgba(0,0,0,.2)"></div>'
               f'<div class="abs" style="left:190px;top:560px;width:700px;height:64px;border-bottom:2px solid rgba(33,29,22,.14);display:flex;align-items:center;padding:0 26px;font-size:26px;color:#6B6255;font-family:G,sans-serif">Downloads</div>'
               f'<div id="icon" class="abs" style="left:440px;top:672px;width:200px;transform-origin:center">{file_icon()}</div>'
               f'<div id="cur" class="abs" style="left:0;top:0">{CURSOR_SVG}</div></div>')
    openrect = '<div id="openrect" class="abs" style="inset:0;background:#211D16;transform-origin:540px 747px;transform:scale(0.001);opacity:0"></div>'
    # recap montage: one beat lifted from each existing reel, compressed
    video = safe('<div class="eb" data-a="3.5" data-b="5.9">BirdMap, <em>in brief</em></div>', top=300, bottom=420, a=None)
    video += f'<div class="abs" data-a="3.7" data-b="5.9" data-y="0" style="left:0;right:0;top:900px;display:flex;justify-content:center">{bird(340, draw=True).replace("class=\"draw\"", "class=\"draw\" data-a=\"3.8\" data-d=\"1.3\"")}</div>'
    video += safe('<h1 data-a="6.0" data-b="8.2" data-d=".7">Every bird you see becomes <em>data that matters.</em></h1>', top=300, bottom=420)
    video += safe('<h1 data-a="8.4" data-b="10.6" data-d=".7">Identify birds <em>by sound.</em></h1>', top=300, bottom=420)
    video += safe('<h1 data-a="10.8" data-b="13.0" data-d=".7">Identified right here, <em>on your phone.</em></h1>', top=300, bottom=420)
    video += safe('<h1 data-a="13.2" data-b="15.4" data-d=".7">BirdMap <em>doesn\'t guess.</em></h1>', top=300, bottom=420)
    video += safe('<h1 data-a="15.6" data-b="17.6" data-d=".7">One pin per place. <em>Works with no signal.</em></h1>', top=300, bottom=420)
    video += safe('<div class="eb">BirdMap</div><h1>See it for <em>yourself.</em></h1><div class="sub">iOS app coming soon. Link in bio.</div><div><span class="pill">Link in bio</span></div>', a=17.8)
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

TRAILER = {'11-see-it-in-action': reel_trailer}

# ------------------------------------------------------------------ CAROUSELS (1080x1350)
def slide_cover(title, eyebrow, hint=True, n=1, total=1):
    body = safe(f'<div class="eb">{eyebrow}</div><h1 style="font-size:116px">{title}</h1>' + ('<div class="sub" style="margin-top:60px">Swipe &rarr;</div>' if hint else ''), top=120, bottom=200)
    return page(body + brandbar(1230)), (1080, 1350)

def slide_point(num, title, sub, n, total):
    body = safe(f'<div class="num">{num}</div><h2 style="margin-top:6px">{title}</h2><div class="sub">{sub}</div>', top=120, bottom=200)
    body += f'<div class="abs" style="right:100px;top:100px;font-size:30px;color:#6B6255">{n}/{total}</div>'
    return page(body + brandbar(1230)), (1080, 1350)

def slide_cta(n, total):
    body = safe('<div class="eb">BirdMap</div><h1>See it on the <em>live map.</em></h1><div class="sub">In your browser now. iOS app coming soon.</div><div><span class="pill">Link in bio</span></div>', top=120, bottom=200)
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
 '01-how-birdmap-works': [('cover', 'How BirdMap <em>works</em>', 'Citizen science for bird lovers'),
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
