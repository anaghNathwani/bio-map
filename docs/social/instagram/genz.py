"""Gen Z-style Reels: hard cuts on the beat, bold captions, pop-in words, emoji stickers, original beat.

Everything is locked to one tempo grid (BPM below) so the picture cuts, the screen kicks and the drums line up.
Video: HTML timeline rendered by build.py (Playwright). Audio: synthesized here (numpy), no samples, no licensing.
Any "app UI" shown is a dramatization and says so on screen.
"""
import numpy as np
import audio as A

BPM = 124
B = 60 / BPM                      # seconds per beat
INK, CLAY, PAPER, LIME = '#14110d', '#C1602E', '#F4F1E9', '#D6FF41'

CSS = """
@font-face{font-family:G;src:url(fonts/geist-latin-wght-normal.woff2);font-weight:100 900}
*{margin:0;padding:0;box-sizing:border-box}
html,body{width:100%;height:100%;overflow:hidden;background:#000;font-family:G,'Apple Color Emoji',sans-serif}
#stage{position:absolute;inset:0}
.scene{position:absolute;inset:0;display:none;overflow:hidden}
.c{position:absolute;left:84px;right:84px;top:280px;bottom:410px;display:flex;flex-direction:column;justify-content:center;gap:30px}
.t{font-weight:860;letter-spacing:-.04em;line-height:.98;font-size:150px}
.t.m{font-size:124px}.t.s{font-size:88px}.t.xs{font-size:60px;letter-spacing:-.02em;font-weight:760}
.k{font-weight:760;font-size:46px;letter-spacing:.01em;opacity:.85}
.row{display:flex;flex-wrap:wrap;gap:.06em .28em}
.hl{display:inline-block;padding:0 .14em;border-radius:.2em}
.em{font-size:210px;line-height:1;display:inline-block}
.pill{display:inline-block;padding:26px 46px;border-radius:999px;font-weight:800;font-size:44px}
.tag{position:absolute;left:0;right:0;text-align:center;font-size:30px;font-weight:600;opacity:.6}
.flash{position:absolute;inset:0;background:#fff;opacity:0;pointer-events:none}
.marq{position:absolute;left:0;white-space:nowrap;font-weight:900;font-size:74px;letter-spacing:-.02em;opacity:.16}
.bubble{padding:34px 44px;border-radius:56px;font-size:70px;font-weight:780;letter-spacing:-.03em;line-height:1.05;max-width:820px}
.card{background:#fff;color:#111;border-radius:64px;padding:52px 56px;box-shadow:0 30px 80px rgba(0,0,0,.28)}
"""

JS = """
const B=%(B)f;
const clamp=x=>Math.min(1,Math.max(0,x));
const oB=x=>{const c1=1.70158,c3=c1+1;return 1+c3*Math.pow(x-1,3)+c1*Math.pow(x-1,2)};
let scenes=[],pops=[],wobs=[],stage,flash;
function init(){
  stage=document.getElementById('stage');flash=document.getElementById('flash');
  scenes=[...document.querySelectorAll('.scene')].map(s=>({el:s,a:+s.dataset.a,b:+s.dataset.b}));
  pops=[...document.querySelectorAll('[data-p]')].map(el=>{const sc=scenes.find(s=>s.el.contains(el));return{el,a:sc.a+(+el.dataset.p)*B,r:+(el.dataset.r||0)}});
  wobs=[...document.querySelectorAll('.wob')];
}
window.render=function(t){
  if(!stage)init();
  let cur=null;
  scenes.forEach(s=>{const on=t>=s.a&&t<s.b;s.el.style.display=on?'block':'none';if(on)cur=s});
  pops.forEach(p=>{const x=clamp((t-p.a)/0.30);const e=x<=0?0:oB(x);p.el.style.opacity=x>0?1:0;p.el.style.transform=`scale(${0.35+0.65*e}) rotate(${p.r*e}deg)`});
  wobs.forEach((w,i)=>{w.style.transform=`rotate(${7*Math.sin(2*Math.PI*1.2*t+i*1.7)}deg) translateY(${6*Math.sin(2*Math.PI*2.4*t+i)}px)`});
  const ph=(t%%B)/B,pulse=1+0.024*Math.exp(-ph*9);
  let dt=cur?t-cur.a:9,first=cur&&cur.a===0;
  const sh=first?0:Math.exp(-dt*16)*16*Math.sin(dt*110);
  stage.style.transform=`translate(${sh}px,${sh*.55}px) scale(${pulse})`;
  flash.style.opacity=first?0:Math.exp(-dt*24)*.5;
  document.querySelectorAll('.marq').forEach((m,i)=>{m.style.transform=`translateX(${-((t*260+i*300)%%1400)}px)`});
  if(window.custom)window.custom(t);
};
""" % {'B': B}


def page(scenes_html, custom=''):
    return (f'<!doctype html><html><head><meta charset="utf-8"><style>{CSS}</style></head><body>'
            f'<div id="stage">{scenes_html}</div><div class="flash" id="flash"></div>'
            f'<script>{JS}{custom}</script></body></html>')


def scene(a, b, bg, fg, inner):
    return f'<div class="scene" data-a="{a * B:.4f}" data-b="{b * B:.4f}" style="background:{bg};color:{fg}">{inner}</div>'


def pop(inner, cls='t', p=0.0, r=0, style='', tag='div'):
    return f'<{tag} class="{cls}" data-p="{p}" data-r="{r}" style="{style}">{inner}</{tag}>'


def words(text, start=0.0, step=0.4, cls='t', hl=(), hlbg=LIME, hlfg=INK, rot=-2):
    """Word-by-word pop-in (like CapCut captions). Words in `hl` get a highlight chip."""
    out = []
    for i, w in enumerate(text.split(' ')):
        inner = w
        if w.strip('.,?!') in hl:
            inner = f'<span class="hl" style="background:{hlbg};color:{hlfg};transform:rotate({rot}deg)">{w}</span>'
        out.append(pop(inner, 'w', start + i * step, 0, tag='span'))
    return f'<div class="row {cls}">{"".join(out)}</div>'


def sticker(emoji, p, left, top, r=10, size=210):
    return (f'<div data-p="{p}" data-r="{r}" style="position:absolute;left:{left}px;top:{top}px"><div class="wob em" style="font-size:{size}px">{emoji}</div></div>')


def marquee(text, top, color):
    return f'<div class="marq" style="top:{top}px;color:{color}">{(text + "  •  ") * 12}</div>'


def cta(a, b, line1='iOS app coming soon', bg=CLAY, fg=PAPER):
    return scene(a, b, bg, fg,
                 marquee('BIRDMAP', 250, fg) + marquee('BIRDMAP', 1560, fg) +
                 '<div class="c">' + pop(line1, 't m', 0) + pop('live map in the browser now', 'k', 0.6) +
                 '<div>' + pop('link in bio', 'pill', 1.0, 0, f'background:{LIME};color:{INK}', 'span') + '</div>' +
                 pop('follow for more bird stuff 🐦', 'k', 1.6) + '</div>')

# ------------------------------------------------------------------ reels
def reel_pov():
    dur = 31 * B
    sc = [
        scene(0, 3, INK, PAPER, '<div class="c">' + pop('pov:', 't s', 0, 0, f'color:{LIME}') + words('you hear a bird', 0.5, 0.45, 't', hl=('bird',)) + '</div>' + sticker('🎧', 1.2, 700, 250, 12, 240)),
        scene(3, 6, CLAY, PAPER, '<div class="c">' + words('and have zero idea what it is', 0, 0.36, 't m', hl=('zero', 'idea'), hlbg=INK, hlfg=LIME) + '</div>' + sticker('😭', 1.8, 690, 1230, -12, 200)),
        scene(6, 10, PAPER, INK, '<div class="c">' + pop('so you record it', 't m', 0) + '<div id="wave" style="position:relative;height:340px;margin-top:20px"></div>' + pop('(up to 30 sec)', 'k', 1.0) + '</div>' + sticker('🎤', 0.5, 700, 260, 10, 220)),
        scene(10, 14, LIME, INK, '<div class="c">' + pop('your phone:', 'k', 0) +
              '<div data-p="0.4" data-r="-2" class="card"><div style="font-size:36px;font-weight:700;opacity:.55">🐦 BirdMap · now</div><div style="font-size:78px;font-weight:850;letter-spacing:-.04em;line-height:1;margin-top:14px">possible match:<br>Western Scrub-Jay</div>'
              '<div style="height:26px;border-radius:14px;background:#e6e2d6;margin-top:30px;overflow:hidden"><div style="width:78%;height:100%;background:#C1602E"></div></div></div>' +
              pop('(dramatization, not real app UI)', 'k', 1.5, 0, 'font-size:32px;opacity:.6') + '</div>'),
        scene(14, 18, INK, PAPER, '<div class="c">' + words('works with no signal', 0, 0.45, 't', hl=('no', 'signal')) + pop('the ID runs on your phone', 'k', 1.9) + '</div>' + sticker('📵', 0.8, 690, 240, 10, 230)),
        scene(18, 22, LIME, INK, '<div class="c">' + words('not sure? it says so', 0, 0.42, 't m', hl=('says',), hlbg=INK, hlfg=LIME) + pop('no cap 🧢', 't m', 2.0, -4) + '</div>'),
        cta(22, 31),
    ]
    wave = """
const wv=document.getElementById('wave');const bars=[];
for(let i=0;i<34;i++){const d=document.createElement('div');d.style.cssText='position:absolute;bottom:0;width:15px;border-radius:8px;background:#C1602E;left:'+(i*29)+'px';wv.appendChild(d);bars.push(d)}
window.custom=function(t){bars.forEach((d,i)=>{const on=t>%f;const k=on?.18+.82*Math.abs(Math.sin(t*9+i*.7)*Math.cos(t*4.3+i*.33)):.06;d.style.height=(k*340)+'px'})};
""" % (6 * B)
    return page(''.join(sc), wave), dur


def reel_signs():
    dur = 30 * B
    def num(n, text, sub, bg, fg, emoji, r=8):
        return ('<div class="c">' + pop(str(n), 't', 0, 0, f'font-size:330px;line-height:.85;color:{LIME if bg != LIME else INK}') +
                words(text, 0.5, 0.34, 't m') + (pop(sub, 'k', 2.4) if sub else '') + '</div>' + sticker(emoji, 0.9, 680, 270, r, 230))
    sc = [
        scene(0, 4, INK, PAPER, '<div class="c">' + words('3 signs you’re becoming a', 0, 0.3, 't m') + words('birder', 1.9, 0.3, 't', hl=('birder',)) + '</div>' + sticker('🔭', 2.4, 690, 1230, 8, 200)),
        scene(4, 9, CLAY, PAPER, num(1, 'you stop mid-sentence because of a chirp', '', CLAY, PAPER, '🤫')),
        scene(9, 14, PAPER, INK, num(2, 'you know what “LBJ” means', '(little brown jobs)', PAPER, INK, '🟤')),
        scene(14, 19, LIME, INK, num(3, 'you have strong opinions about gulls', '', LIME, INK, '🌊')),
        scene(19, 24, INK, PAPER, '<div class="c">' + words('so log them all', 0, 0.42, 't', hl=('all',)) + pop('every sighting, on a map 🗺️', 'k', 1.9) + '</div>'),
        cta(24, 30, 'which one are you? 👇'),
    ]
    return page(''.join(sc)), dur


def reel_speedrun():
    dur = 26 * B
    def step(n, text, emoji, bg, fg, sub=''):
        return ('<div class="c">' + pop(f'step {n}', 'k', 0, 0, 'font-size:54px') + words(text, 0.25, 0.32, 't m') + (pop(sub, 'k', 1.8) if sub else '') + '</div>' + sticker(emoji, 0.6, 690, 250, 10, 240))
    prog = lambda k: ('<div style="position:absolute;left:84px;right:84px;top:200px;display:flex;gap:14px">' +
                      ''.join(f'<div style="flex:1;height:14px;border-radius:8px;background:currentColor;opacity:{1 if i < k else .22}"></div>' for i in range(4)) + '</div>')
    sc = [
        scene(0, 2, INK, PAPER, '<div class="c">' + words('how BirdMap works', 0, 0.3, 't m') + pop('speedrun ⚡', 't', 1.0, -3, f'color:{LIME}') + '</div>'),
        scene(2, 5, CLAY, PAPER, prog(1) + step(1, 'take a photo', '📸', CLAY, PAPER, 'or record a bird call')),
        scene(5, 8, INK, PAPER, prog(2) + step(2, 'your phone IDs it', '🧠', INK, PAPER, '(no upload needed)')),
        scene(8, 11, PAPER, INK, prog(3) + step(3, 'birders confirm it', '✅', PAPER, INK, 'or correct it. or say unsure')),
        scene(11, 14, LIME, INK, prog(4) + step(4, 'it lands on the map', '📍', LIME, INK, 'one pin per place')),
        scene(14, 18, INK, PAPER, '<div class="c">' + words('that’s it. that’s the app.', 0, 0.38, 't m', hl=('app.',)) + '</div>' + sticker('🫡', 1.8, 690, 1230, 8, 200)),
        cta(18, 26),
    ]
    return page(''.join(sc)), dur


def reel_unsure():
    dur = 30 * B
    sc = [
        scene(0, 4, PAPER, INK, '<div class="c">' + words('me pretending I know every bird', 0, 0.34, 't m', hl=('every',), hlbg=CLAY, hlfg=PAPER) + '</div>' + sticker('😌', 2.2, 690, 1230, -8, 200)),
        scene(4, 8, INK, PAPER, '<div class="c">' + pop('BirdMap:', 'k', 0) +
              '<div data-p="0.5" data-r="-2" class="bubble" style="background:%s;color:%s;align-self:flex-start">not sure ngl 🤷</div>' % (CLAY, PAPER) +
              pop('(dramatization)', 'k', 2.0, 0, 'font-size:32px;opacity:.55') + '</div>'),
        scene(8, 12, LIME, INK, '<div class="c">' + words('the bravest thing an app can do', 0, 0.4, 't m', hl=('bravest',), hlbg=INK, hlfg=LIME) + '</div>'),
        scene(12, 17, CLAY, PAPER, '<div class="c">' + words('low confidence?', 0, 0.4, 't m') + pop('it tells you instead of guessing', 't s', 1.6) + '</div>' + sticker('🫶', 2.6, 690, 1230, 8, 200)),
        scene(17, 22, INK, PAPER, '<div class="c">' + words('then other birders can help', 0, 0.36, 't m', hl=('help',)) + pop('confirm it · correct it · mark unsure', 'k', 2.4) + '</div>'),
        scene(22, 25, PAPER, INK, '<div class="c">' + words('growth mindset for bird apps', 0, 0.36, 't m', hl=('growth',), hlbg=LIME, hlfg=INK) + '</div>' + sticker('📈', 1.8, 690, 260, 6, 210)),
        cta(25, 30),
    ]
    return page(''.join(sc)), dur


REELS = {'05-pov-you-hear-a-bird': reel_pov, '06-3-signs-youre-a-birder': reel_signs,
         '07-how-it-works-speedrun': reel_speedrun, '08-not-sure-is-valid': reel_unsure}

# ------------------------------------------------------------------ audio
SRr = A.SR
NOTE = lambda m: 440 * 2 ** ((m - 69) / 12)


def kick(dur=0.32, amp=0.9):
    t = A.t_axis(dur)
    f = 46 + 110 * np.exp(-t * 32)
    return amp * np.tanh(1.8 * np.sin(2 * np.pi * np.cumsum(f) / SRr)) * np.exp(-t / 0.13) * np.minimum(1, t / 0.002)


def clap(dur=0.28, amp=0.34):
    t = A.t_axis(dur)
    n = A.rng.standard_normal(len(t))
    n = n - np.convolve(n, np.ones(30) / 30, mode='same')
    bursts = sum(np.exp(-np.maximum(t - o, 0) / 0.05) * (t >= o) for o in (0, 0.012, 0.024))
    return amp * n * bursts * np.exp(-t / 0.07)


def hat(dur=0.09, amp=0.085):
    t = A.t_axis(dur)
    n = A.rng.standard_normal(len(t))
    n = n - np.convolve(n, np.ones(6) / 6, mode='same')
    return amp * n * np.exp(-t / 0.018)


def sub(freq, dur, amp=0.42):
    t = A.t_axis(dur)
    env = np.minimum(1, t / 0.01) * np.exp(-t / (dur * 0.7))
    return amp * env * np.tanh(2.2 * np.sin(2 * np.pi * freq * t))


def blip(at_hz0, at_hz1, dur=0.09, amp=0.22):
    t = A.t_axis(dur)
    f = at_hz0 + (at_hz1 - at_hz0) * (t / dur)
    return amp * np.sin(2 * np.pi * np.cumsum(f) / SRr) * np.exp(-t / (dur * 0.6))


def whoosh(dur=0.4, amp=0.15):
    t = A.t_axis(dur)
    n = A.rng.standard_normal(len(t))
    lo = np.convolve(n, np.ones(int(20 + 200 * (1 - 0)))/(20+200), mode='same')
    env = np.sin(np.pi * np.clip(t / dur, 0, 1)) ** 2
    return amp * env * (n - lo) * 0.7


def boom(dur=0.7, amp=0.5):
    t = A.t_axis(dur)
    return amp * np.sin(2 * np.pi * np.cumsum(70 * np.exp(-t * 3) + 35) / SRr) * np.exp(-t / 0.25)


PROG = [(45, [69, 76, 72]), (41, [65, 72, 69]), (48, [67, 72, 76]), (43, [67, 71, 74])]  # Am F C G: (bass midi, arp chord)


def track(dur, cuts, riser_to=None, bass_style=0):
    b = np.zeros((int(dur * SRr), 2))
    nb = int(dur / B) + 1
    for k in range(nb):
        at = k * B
        place = A.place
        place(b, kick(), at)
        if k % 2 == 1: place(b, clap(), at)
        place(b, hat(), at + B / 2, 0.3)
        if k % 4 == 3: place(b, hat(0.09, 0.06), at + B * 0.75, -0.3)
        bar, pos = divmod(k, 4)
        root, chord = PROG[bar % 4]
        place(b, sub(NOTE(root), B * 0.9), at + (B / 2 if pos % 2 == 1 else 0) if bass_style else at + B / 2)
        for j in range(2):  # 8th-note arp
            note = chord[(k * 2 + j) % len(chord)] + (12 if (k * 2 + j) % 5 == 4 else 0)
            place(b, A.pluck(NOTE(note), 0.5, 0.09), at + j * B / 2, 0.35 if j else -0.35)
    for c in cuts:  # every scene change: whoosh into it + hit on it
        A.place(b, whoosh(), max(0, c * B - 0.28))
        A.place(b, boom(0.6, 0.35), c * B)
        A.place(b, blip(900, 1500), c * B + 0.02)
    if riser_to:
        t0 = (riser_to - 4) * B
        t = A.t_axis(4 * B)
        n = A.rng.standard_normal(len(t)); n = n - np.convolve(n, np.ones(12) / 12, mode='same')
        A.place(b, 0.16 * n * (t / t[-1]) ** 2 + 0.06 * np.sin(2 * np.pi * np.cumsum(300 + 1400 * (t / t[-1]) ** 2) / SRr), t0)
    return b


def pop_sfx(b, beats):
    for x in beats: A.place(b, blip(700, 420, 0.07, 0.13), x * B)


A.BUILDERS.update({
    '05-pov-you-hear-a-bird': lambda dur: track(dur, [3, 6, 10, 14, 18, 22], riser_to=22),
    '06-3-signs-youre-a-birder': lambda dur: track(dur, [4, 9, 14, 19, 24], riser_to=24, bass_style=1),
    '07-how-it-works-speedrun': lambda dur: track(dur, [2, 5, 8, 11, 14, 18], riser_to=18),
    '08-not-sure-is-valid': lambda dur: track(dur, [4, 8, 12, 17, 22, 25], riser_to=25, bass_style=1),
})
