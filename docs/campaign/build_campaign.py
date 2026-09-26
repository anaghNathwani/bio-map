"""BirdMap brand campaign: "Look up."  Film (9:16, 16:9, cut-downs) and poster ads.

Everything is generated: the flock is a seeded boids simulation, the type is the brand's Fraunces/Geist, the score is
synthesized (see score.py). No stock footage, no photos, no samples: nothing to license.

  python3 build_campaign.py test       # a few stills to check the look
  python3 build_campaign.py posters
  python3 build_campaign.py film       # renders all films (several minutes)
"""
import json, pathlib, shutil, subprocess, sys, tempfile

HERE = pathlib.Path(__file__).parent
SRC = HERE / 'src'
FONTS = '../../social/instagram/src/fonts'
FLOCK = (HERE / 'flock.js').read_text()
BIRD_PATH = "M6 27C11 14 21 7 34 7c2.7 0 5 .4 7 1.1-1.8 1-3.3 2.3-4.4 4C40 12.4 43 13.4 45 15.3c-3 .3-5.6 1.4-7.7 3.2 1 6.7-1.2 13-6.4 17.6C25.8 41.4 18.8 43.6 11 42.4c3.6-1 6.6-2.9 8.8-5.5-5-.4-9.4-3-12.2-7.1 2.6.7 5.1.6 7.4-.4C11 27.8 7.9 25 6 21.2"
def bird(size, color='#fff', sw=2.1, extra=''):
    return (f'<svg {extra} viewBox="0 0 48 48" width="{size}" height="{size}" fill="none" stroke="{color}" stroke-width="{sw}" '
            f'stroke-linecap="round" stroke-linejoin="round"><path d="{BIRD_PATH}"/><circle cx="33.5" cy="14.5" r="1.4" fill="{color}" stroke="none"/></svg>')

FLOCK_P = dict(coh=.0016, ali=.18, sep=34, sepR2=900, att=.0026, attY=.0032, R=650, speed=4.2, k=7)
LOOK = dict(alpha=[.55, .8, 1], lw=[1.6, 2.2, 3.0], len=.010, frame=.34, p=FLOCK_P)
DARK = dict(bg='#000', bgFade='rgba(0,0,0,.34)', fg='#fff')
LIGHT = dict(bg='#f4f1e9', bgFade='rgba(244,241,233,.34)', fg='#14110d')

CSS = """
@font-face{font-family:F;src:url(%(f)s/fraunces-latin-standard-normal.woff2);font-weight:100 900}
@font-face{font-family:F;font-style:italic;src:url(%(f)s/fraunces-latin-wght-italic.woff2);font-weight:100 900}
@font-face{font-family:G;src:url(%(f)s/geist-latin-wght-normal.woff2);font-weight:100 900}
*{margin:0;padding:0;box-sizing:border-box}
html,body{width:100%%;height:100%%;overflow:hidden;background:%(bg)s}
canvas{position:absolute;inset:0}
#txt{position:absolute;inset:0;pointer-events:none}
.line{position:absolute;left:8%%;right:8%%;text-align:center;font-family:F,serif;font-weight:400;color:%(ink)s;
  line-height:1.12;letter-spacing:-.012em;opacity:0;text-shadow:%(shadow)s}
.line em{font-style:italic}
.small{font-family:G,sans-serif;font-size:.42em;letter-spacing:.24em;text-transform:uppercase;font-weight:500}
.mark{position:absolute;left:0;right:0;display:flex;flex-direction:column;align-items:center;opacity:0}
""" 

def page(cfg_js, body='', css_extra='', dark=True):
    css = CSS % dict(f=FONTS, bg='#000' if dark else '#f4f1e9', ink='#fff' if dark else '#14110d',
                     shadow='0 0 28px #000,0 0 6px #000' if dark else '0 0 24px #f4f1e9')
    return (f'<!doctype html><html><head><meta charset="utf-8"><style>{css}{css_extra}</style></head><body>'
            f'<canvas id="cv"></canvas><div id="txt"></div>{body}<script>window.CFG={cfg_js};</script><script>{FLOCK}</script></body></html>')

def js(obj):
    """JSON with raw JS functions allowed via {'__js': 'code'} markers."""
    s = json.dumps(obj)
    import re
    return re.sub(r'\{"__js": "((?:[^"\\]|\\.)*)"\}', lambda m: json.loads('"' + m.group(1) + '"'), s)

def F(code): return {'__js': code}

# ------------------------------------------------------------------ the manifesto
# (start, end, html)  seconds.  Original writing. `hi` marks the key beat.
LINES = [
    (1.0, 4.8, 'To the ones who stop<br>mid-sentence.'),
    (5.6, 9.4, 'Who hear something<br>the rest of us<br>walked past.'),
    (10.2, 13.6, 'Who <em>look up.</em>'),
    (14.4, 19.0, 'They’re in no hurry.<br>They have somewhere to be,<br>and it’s right here.'),
    (19.8, 23.8, 'They know the little brown<br>one from the other<br>little brown one.'),
    (24.6, 29.6, 'They write it down.<br><em>Where. When.<br>What it sounded like.</em>'),
    (30.4, 33.2, 'Nobody asked them to.'),
    (33.6, 36.4, '<em>Someone should.</em>'),
    (37.4, 41.8, 'One bird is a small fact.<br>A place, a time, a name.'),
    (42.6, 47.6, 'A thousand of them,<br>and you can watch<br>a whole sky move.'),
    (48.6, 53.4, 'You’re not watching birds.<br><em>You’re the one<br>who noticed.</em>'),
]
END_A = 55.0
DUR = 63.0

def film_html(w, h, lines=LINES, dur=DUR, end_a=END_A, speed=1.0, ramp=(2, 46), seed=11):
    portrait = h > w
    size = (w * 0.078) if portrait else (h * 0.072)
    ln = [dict(a=a / speed, b=b / speed, html=t, fi=1.2, fo=.9, cls='') for a, b, t in lines]
    base_y = .70 if portrait else .74
    css = f'.line{{top:{base_y*100:.0f}%;font-size:{size:.0f}px;transform:translateY(0)}}'
    css += f'.mark .wm{{font-family:G,sans-serif;font-weight:500;letter-spacing:.42em;font-size:{size*.36:.0f}px;color:#fff;margin-top:{size*.55:.0f}px;text-indent:.42em}}'
    css += f'.mark .lu{{font-family:F,serif;font-style:italic;font-size:{size*1.9:.0f}px;color:#fff;margin-top:{size*.5:.0f}px;letter-spacing:-.02em}}'
    css += f'.mark .soon{{font-family:G,sans-serif;font-size:{size*.3:.0f}px;letter-spacing:.2em;text-transform:uppercase;color:#9b968a;margin-top:{size*.8:.0f}px}}'
    body = (f'<div class="mark" id="end" style="top:{(30 if portrait else 24)}%">{bird(int(size*3.3), "#fff", 1.8)}'
            f'<div class="lu">Look up.</div><div class="wm">BIRDMAP</div></div>')
    N = 3000 if portrait else 3400
    cfg = dict(seed=seed, n=N, warm=500, cy=.34 if portrait else .40, lines=ln, **DARK, **{**LOOK, 'frame': .30 if portrait else .32},
               visible=F(f't=>Math.min({N},120+{N-120}*ease((t-{ramp[0]/speed})/{(ramp[1]-ramp[0])/speed}))'),
               lift=F('t=>t>9.6&&t<16?Math.min(1,(t-9.6)/2)*(t<12?70:70*(1-(t-12)/4)):0'),
               cam=F('t=>({yaw:t*.045,off:0})'),
               end=F(f'(t,ease)=>{{const e=document.getElementById("end");const a=ease((t-{end_a/speed})/2.2);e.style.opacity=a;e.style.filter="blur("+((1-a)*14)+"px)";'
                     f'const fade=1-.75*ease((t-{end_a/speed})/2.4);cv.style.opacity=fade}}'))
    return page(js(cfg), body, css, dark=True)

# ------------------------------------------------------------------ posters (still frames)
def poster_html(w, h, headline, sub='', dark=True, steps=60, seed=5, cy=.31, size_k=1.0, foot='BIRDMAP'):
    style = DARK if dark else LIGHT
    ink = '#fff' if dark else '#14110d'
    soft = '#9b968a' if dark else '#6b6255'
    fs = (w * .108) * size_k
    css = (f'.p{{position:absolute;left:8%;right:8%;bottom:{h*.115:.0f}px;font-family:F,serif;color:{ink};font-size:{fs:.0f}px;line-height:1.04;letter-spacing:-.02em}}'
           f'.p em{{font-style:italic}}.s{{font-family:G,sans-serif;font-size:{w*.032:.0f}px;line-height:1.5;color:{soft};margin-top:{h*.02:.0f}px;letter-spacing:.01em;max-width:80%}}'
           f'.foot{{position:absolute;left:8%;right:8%;bottom:{h*.045:.0f}px;display:flex;align-items:center;gap:16px;font-family:G,sans-serif;font-size:{w*.022:.0f}px;letter-spacing:.24em;color:{soft}}}')
    body = f'<div class="p">{headline}<div class="s">{sub}</div></div><div class="foot">{bird(int(w*.045), ink, 2.2)}<span>{foot}</span></div>'
    look = dict(LOOK) if dark else dict(LOOK, alpha=[.6, .8, .95], blend='source-over')
    cfg = dict(seed=seed, n=3000, warm=500, cy=cy, still=True, stillSteps=steps, trails=False, **style, lines=[], **look)
    return page(js(cfg), body, css, dark=dark)

POSTERS = {
    '01-look-up': ('<em>Look up.</em>', 'Somewhere above you, something is happening. Most of us walk right under it.', True, 40, 5),
    '02-mid-sentence': ('To the ones who stop mid-sentence.', 'Who hear something the rest of us walked past.', True, 90, 8),
    '03-a-thousand': ('A thousand small facts, and you can watch a sky move.', 'One bird is a place, a time, a name. Together, they’re a picture of the world.', True, 150, 11),
    '04-the-one-who-noticed': ('You’re not watching birds. <em>You’re the one who noticed.</em>', 'Notice one more thing today.', False, 70, 3),
}

def shot(pg, name, html, w, h, out, t=0):
    p = SRC / f'{name}.html'; p.write_text(html)
    pg.set_viewport_size({'width': w, 'height': h}); pg.goto(p.as_uri()); pg.evaluate('document.fonts.ready'); pg.wait_for_timeout(300)
    pg.evaluate(f'render({t})'); pg.screenshot(path=str(out), type='png')

def render_video(pg, name, html, w, h, dur, out, fps=30):
    p = SRC / f'{name}.html'; p.write_text(html)
    pg.set_viewport_size({'width': w, 'height': h}); pg.goto(p.as_uri()); pg.evaluate('document.fonts.ready'); pg.wait_for_timeout(400)
    tmp = pathlib.Path(tempfile.mkdtemp()); n = int(dur * fps)
    for i in range(n):
        pg.evaluate(f'render({i / fps})'); pg.screenshot(path=str(tmp / f'{i:05d}.jpg'), type='jpeg', quality=93)
        if i % 300 == 0: print('  frame', i, '/', n, flush=True)
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-framerate', str(fps), '-i', str(tmp / '%05d.jpg'),
                    '-vf', 'scale=in_range=pc:out_range=tv:out_color_matrix=bt709,format=yuv420p', '-c:v', 'libx264', '-preset', 'slow', '-crf', '17',
                    '-profile:v', 'high', '-colorspace', 'bt709', '-color_primaries', 'bt709', '-color_trc', 'bt709', '-color_range', 'tv',
                    '-movflags', '+faststart', str(out)], check=True)
    shutil.rmtree(tmp); print('video', out.name, f'{out.stat().st_size/1e6:.1f} MB')

CUT15 = [(0.8, 3.8, 'To the ones who stop<br>mid-sentence.'), (4.4, 7.0, 'Who <em>look up.</em>'),
         (7.6, 11.2, 'A thousand small facts,<br>and you can watch<br>a sky move.'), (11.8, 13.0, 'You’re the one<br><em>who noticed.</em>')]
BUMP = [(0.7, 3.4, 'To the ones<br>who <em>look up.</em>')]
FILMS = {   # name: (w, h, html kwargs, duration, score cues (notes start, swell, peak, end))
    'look-up-60s-9x16': (1080, 1920, dict(), 63.0, (9.5, 41.0, 48.6, 55.0)),
    'look-up-60s-16x9': (1920, 1080, dict(), 63.0, (9.5, 41.0, 48.6, 55.0)),
    'look-up-15s-9x16': (1080, 1920, dict(lines=CUT15, end_a=13.4, ramp=(0.5, 10.5)), 19.0, (1.0, 8.0, 12.2, 13.4)),
    'look-up-6s-9x16': (1080, 1920, dict(lines=BUMP, end_a=3.7, ramp=(0.3, 3.4)), 8.0, (0.6, 1.5, 3.0, 3.7)),
}


def main(which):
    from playwright.sync_api import sync_playwright
    with sync_playwright() as p:
        b = p.chromium.launch(channel='chrome'); pg = b.new_page()
        if which == 'test':
            shot(pg, 'test-film-916', film_html(1080, 1920), 1080, 1920, HERE / 'film' / 'test-916.png', t=46)
            shot(pg, 'test-film-169', film_html(1920, 1080), 1920, 1080, HERE / 'film' / 'test-169.png', t=46)
        if which in ('all', 'posters'):
            for name, (hl, sub, dark, steps, seed) in POSTERS.items():
                shot(pg, 'poster-' + name, poster_html(1080, 1350, hl, sub, dark, steps, seed), 1080, 1350, HERE / 'posters' / f'{name}-4x5.png')
                shot(pg, 'poster-s-' + name, poster_html(1080, 1920, hl, sub, dark, steps, seed, cy=.32), 1080, 1920, HERE / 'posters' / f'{name}-story.png')
        if which in ('all', 'film'):
            import score
            for name, (w, h, kw, dur, cues) in FILMS.items():
                if len(sys.argv) > 2 and sys.argv[2] not in name: continue
                out = HERE / 'film' / f'{name}.mp4'
                print('rendering', name, flush=True)
                render_video(pg, name, film_html(w, h, dur=dur, **kw), w, h, dur, out)
                score.mux(out, dur, cues)
        b.close()

if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else 'all')
