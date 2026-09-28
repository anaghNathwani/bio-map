"""BirdMap brand campaign: "Look up."  Films (9:16, 16:9, cut-downs) and posters.

The campaign is about the thought, not the product: it never mentions the app.
Everything is generated: the flock is a seeded boids simulation, the type is the brand serif, the narration is local neural
TTS (vo.py) and the score is synthesized (score.py). No stock footage, photos or samples: nothing to license.

  python3 build_campaign.py posters
  python3 build_campaign.py film [name-filter]      # films are timed from the narration
  python3 build_campaign.py test                    # stills to check the look
"""
import json, pathlib, re, shutil, subprocess, sys, tempfile

HERE = pathlib.Path(__file__).parent
SRC = HERE / 'src'
FONTS = '../../social/instagram/src/fonts'
FLOCK = (HERE / 'flock.js').read_text()
BIRD_PATH = "M6 27C11 14 21 7 34 7c2.7 0 5 .4 7 1.1-1.8 1-3.3 2.3-4.4 4C40 12.4 43 13.4 45 15.3c-3 .3-5.6 1.4-7.7 3.2 1 6.7-1.2 13-6.4 17.6C25.8 41.4 18.8 43.6 11 42.4c3.6-1 6.6-2.9 8.8-5.5-5-.4-9.4-3-12.2-7.1 2.6.7 5.1.6 7.4-.4C11 27.8 7.9 25 6 21.2"
def bird(size, color='#fff', sw=2.1):
    return (f'<svg viewBox="0 0 48 48" width="{size}" height="{size}" fill="none" stroke="{color}" stroke-width="{sw}" '
            f'stroke-linecap="round" stroke-linejoin="round"><path d="{BIRD_PATH}"/><circle cx="33.5" cy="14.5" r="1.4" fill="{color}" stroke="none"/></svg>')

# Slow, wide, gentle: no bursts. (see flock.js for what each knob does)
FLOCK_P = dict(coh=.0007, ali=.10, sep=26, sepR2=1100, att=.0016, attY=.0020, R=900, speed=1.9, k=7, cell=70, spread=420)
LOOK = dict(alpha=[.5, .75, .95], lw=[1.5, 2.0, 2.8], len=.012, p=FLOCK_P, logoPath=BIRD_PATH, logoSw=2.2, dot=1.7)
DARK = dict(bg='#000', fg='#fff')
LIGHT = dict(bg='#f4f1e9', fg='#14110d')

CSS = """
@font-face{font-family:F;src:url(%(f)s/fraunces-latin-standard-normal.woff2);font-weight:100 900}
@font-face{font-family:F;font-style:italic;src:url(%(f)s/fraunces-latin-wght-italic.woff2);font-weight:100 900}
@font-face{font-family:G;src:url(%(f)s/geist-latin-wght-normal.woff2);font-weight:100 900}
*{margin:0;padding:0;box-sizing:border-box}
html,body{width:100%%;height:100%%;overflow:hidden;background:%(bg)s}
canvas{position:absolute;inset:0}
#txt{position:absolute;inset:0;pointer-events:none}
.line{position:absolute;left:8%%;right:8%%;text-align:center;font-family:F,serif;font-weight:400;color:%(ink)s;
  line-height:1.14;letter-spacing:-.012em;opacity:0;text-shadow:%(shadow)s}
.line em{font-style:italic}
.mark{position:absolute;left:0;right:0;display:flex;flex-direction:column;align-items:center;opacity:0}
"""

def js(obj):
    s = json.dumps(obj)
    return re.sub(r'\{"__js": "((?:[^"\\]|\\.)*)"\}', lambda m: json.loads('"' + m.group(1) + '"'), s)
def F(code): return {'__js': code}

def page(cfg, body='', css_extra='', dark=True):
    css = CSS % dict(f=FONTS, bg='#000' if dark else '#f4f1e9', ink='#fff' if dark else '#14110d',
                     shadow='0 0 28px #000,0 0 6px #000' if dark else '0 0 24px #f4f1e9')
    return (f'<!doctype html><html><head><meta charset="utf-8"><style>{css}{css_extra}</style></head><body>'
            f'<canvas id="cv"></canvas><div id="txt"></div>{body}<script>window.CFG={js(cfg)};</script><script>{FLOCK}</script></body></html>')

# ------------------------------------------------------------------ the script (original writing; abstract, tied to the living world)
# say = what is spoken, show = what is on screen, gap = silence after the line (seconds)
FULL = [
    dict(say='Above the stone, below the stars, a thin bright layer where everything is alive.',
         show=('Above the stone,<br>below the stars,<br>a thin bright layer<br>where everything is <em>alive.</em>',
               'Above the stone, below the stars,<br>a thin bright layer<br>where everything is <em>alive.</em>'), gap=1.6),
    dict(say='We call it the biosphere. The birds call it home.',
         show='We call it the biosphere.<br><em>The birds call it home.</em>', gap=1.5),
    dict(say='Every morning, it clears its throat.', show='Every morning,<br>it <em>clears its throat.</em>', gap=0.8),
    dict(say='And a few of us stop mid-sentence.', show='And a few of us<br>stop mid-sentence.', gap=1.8),
    dict(say='They are the listeners. The sky is a language.',
         show='They are the listeners.<br><em>The sky is a language.</em>', gap=1.6),
    dict(say='Wings are its punctuation. Migration is the long sentence, written across the seasons.',
         show=('Wings are its punctuation.<br><em>Migration is the<br>long sentence, written<br>across the seasons.</em>',
               'Wings are its punctuation.<br><em>Migration is the long sentence,<br>written across the seasons.</em>'), gap=1.7),
    dict(say='One bird is a small fact. A thousand of them move like a single thought.',
         show='One bird is a small fact.<br>A thousand of them<br><em>move like a single thought.</em>', gap=2.8),
    dict(say='Nobody asked them to write it down. Someone should.',
         show='Nobody asked them<br>to write it down.<br><em>Someone should.</em>', gap=3.8, hold=2.4),
    dict(say='To the ones who look up. The world keeps a diary. You are its handwriting.',
         show='To the ones who <em>look up.</em><br>The world keeps a diary.<br>You are its handwriting.', gap=0.4),
]
SHORT = [FULL[4], FULL[6]]
BUMPER = [dict(say='To the ones who look up.', show='To the ones<br>who <em>look up.</em>', gap=0.2)]
FINAL = 'Look up.'

FILMS = {   # name: (w, h, script, intro seconds, formation seconds)
    'look-up-film-9x16': (1080, 1920, FULL, 4.0, 7.5),
    'look-up-film-16x9': (1920, 1080, FULL, 4.0, 7.5),
    'look-up-short-9x16': (1080, 1920, SHORT, 2.5, 5.5),
    'look-up-bumper-9x16': (1080, 1920, BUMPER, 1.5, 4.0),
}

def plan(script, intro, form_dur):
    """Turn the script into a timeline from the measured narration lengths."""
    import vo
    t = intro; items = []; events = []
    for L in script:
        d = vo.duration(L['say']); p = vo.synth(L['say'])[0]
        a = t; vs = a + 0.55; ve = vs + d
        items.append((a, ve + 0.9, L['show'])); events.append((vs, p))
        t = ve + L['gap']
    form_a = t + 0.2
    fin_p = vo.synth(FINAL)[0]; fin_d = vo.duration(FINAL)
    fin_at = form_a + form_dur * 0.78
    events.append((fin_at, fin_p))
    dur = fin_at + fin_d + 5.0
    return dict(items=items, events=events, form_a=form_a, form_dur=form_dur, fin_at=fin_at, dur=dur)

def film_html(w, h, pl):
    portrait = h > w
    size = (w * 0.054) if portrait else (h * 0.050)
    S = min(w, h)
    logo_px = S * (.44 if portrait else .50)
    cy = .35 if portrait else .41
    pick = lambda t: (t[0] if portrait else t[1]) if isinstance(t, tuple) else t      # (portrait, landscape) line breaks
    ln = [dict(a=a, b=b, html=pick(t), fi=1.4, fo=1.3) for a, b, t in pl['items']]
    text_top = int(cy * h + logo_px * .47 + size * .35)
    css = f'.line{{top:{(.70 if portrait else .74)*100:.0f}%;font-size:{size:.0f}px}}'
    css += f'.mark .lu{{font-family:F,serif;font-style:italic;font-size:{size*1.9:.0f}px;color:#fff;letter-spacing:-.02em}}'
    css += f'.mark .wm{{font-family:G,sans-serif;font-weight:500;letter-spacing:.42em;font-size:{size*.36:.0f}px;color:#fff;margin-top:{size*.5:.0f}px;text-indent:.42em}}'
    body = f'<div class="mark" id="end" style="top:{text_top}px"><div class="lu">Look up.</div><div class="wm">BIRDMAP</div></div>'
    fin = pl['fin_at']
    cfg = dict(seed=11, n=3000 if portrait else 3400, warm=500, cy=cy, frame=.30 if portrait else .27, lines=ln, **DARK, **LOOK,
               form=dict(a=pl['form_a'], dur=pl['form_dur'], cx=.5, cy=cy, size=logo_px),
               reveal=F('t=>ease((t-.4)/7)'), trail=.24,
               lift=F('t=>0'), cam=F('t=>({yaw:t*.02,off:0})'),
               end=F(f'(t,ease)=>{{const a=ease((t-{fin - 0.6:.3f})/1.8);const e=document.getElementById("end");e.style.opacity=a;e.style.filter="blur("+((1-a)*10)+"px)"}}'))
    return page(cfg, body, css, dark=True)

# ------------------------------------------------------------------ posters (still frames)
def poster_html(w, h, headline, sub='', dark=True, steps=60, seed=5, cy=.31, form=False, foot='BIRDMAP'):
    style = DARK if dark else LIGHT
    ink = '#fff' if dark else '#14110d'; soft = '#9b968a' if dark else '#6b6255'
    fs = w * .108
    css = (f'.p{{position:absolute;left:8%;right:8%;bottom:{h*.115:.0f}px;font-family:F,serif;color:{ink};font-size:{fs:.0f}px;line-height:1.04;letter-spacing:-.02em}}'
           f'.p em{{font-style:italic}}.s{{font-family:G,sans-serif;font-size:{w*.032:.0f}px;line-height:1.5;color:{soft};margin-top:{h*.02:.0f}px;letter-spacing:.01em;max-width:80%}}'
           f'.foot{{position:absolute;left:8%;right:8%;bottom:{h*.045:.0f}px;display:flex;align-items:center;gap:16px;font-family:G,sans-serif;font-size:{w*.022:.0f}px;letter-spacing:.24em;color:{soft}}}')
    body = f'<div class="p">{headline}' + (f'<div class="s">{sub}</div>' if sub else '') + f'</div><div class="foot">{bird(int(w*.045), ink, 2.2)}<span>{foot}</span></div>'
    look = dict(LOOK) if dark else dict(LOOK, alpha=[.6, .8, .95], blend='source-over')
    cfg = dict(seed=seed, n=3000, warm=500, cy=cy, frame=.30, still=True, stillSteps=steps, trails=False, **style, lines=[], **look)
    if form:
        cfg.update(form=dict(a=0, dur=1, cx=.5, cy=cy, size=min(w, h) * .50), stillForm=1)
    return page(cfg, body, css, dark=dark)

POSTERS = {   # name: (headline, sub, dark, sim steps, seed, forms the mark)
    '01-look-up': ('<em>Look up.</em>', 'The sky is a language.', True, 60, 5, False),
    '02-clears-its-throat': ('Every morning, it clears its throat.', 'And a few of us stop mid-sentence.', True, 140, 8, False),
    '03-single-thought': ('One bird is a small fact. A thousand of them <em>move like a single thought.</em>', '', True, 220, 11, False),
    '04-handwriting': ('The world keeps a diary. <em>You are its handwriting.</em>', '', False, 120, 3, False),
    '05-mark': ('<em>Look up.</em>', '', True, 60, 5, True),
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
                    '-vf', 'scale=in_range=pc:out_range=tv:out_color_matrix=bt709,format=yuv420p', '-c:v', 'libx264', '-preset', 'slow', '-crf', '23',
                    '-profile:v', 'high', '-colorspace', 'bt709', '-color_primaries', 'bt709', '-color_trc', 'bt709', '-color_range', 'tv',
                    '-movflags', '+faststart', str(out)], check=True)
    shutil.rmtree(tmp); print('video', out.name, f'{out.stat().st_size/1e6:.1f} MB')

def main(which):
    from playwright.sync_api import sync_playwright
    with sync_playwright() as p:
        b = p.chromium.launch(channel='chrome'); pg = b.new_page()
        if which == 'test':
            pl = plan(FULL, 4.0, 7.5)
            print('film length', round(pl['dur'], 1), 's; formation starts', round(pl['form_a'], 1))
            for tt, tag in [(30, 'flock'), (pl['form_a'] - 4, 'gather'), (pl['form_a'] + 3.4, 'forming'), (pl['form_a'] + 7.6, 'mark')]:
                shot(pg, f'test-{tag}', film_html(1080, 1920, pl), 1080, 1920, HERE / 'film' / f'test-{tag}.png', t=tt)
        if which in ('all', 'posters'):
            for name, (hl, sub, dark, steps, seed, form) in POSTERS.items():
                shot(pg, 'poster-' + name, poster_html(1080, 1350, hl, sub, dark, steps, seed, form=form), 1080, 1350, HERE / 'posters' / f'{name}-4x5.png')
                shot(pg, 'poster-s-' + name, poster_html(1080, 1920, hl, sub, dark, steps, seed, cy=.32, form=form), 1080, 1920, HERE / 'posters' / f'{name}-story.png')
        if which in ('all', 'film'):
            import score
            for name, (w, h, script, intro, fd) in FILMS.items():
                if len(sys.argv) > 2 and sys.argv[2] not in name: continue
                pl = plan(script, intro, fd)
                out = HERE / 'film' / f'{name}.mp4'
                print('rendering', name, f"{pl['dur']:.1f}s", flush=True)
                render_video(pg, name, film_html(w, h, pl), w, h, pl['dur'], out)
                score.mux(out, pl['dur'], (intro + 1.0, pl['form_a'] - 5, pl['form_a'] + pl['form_dur'] * 0.6, pl['fin_at'] + 1.0), pl['events'])
        b.close()

if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else 'all')
