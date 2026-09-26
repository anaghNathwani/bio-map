"""Original score for the "Look up." films: a slow felt-piano figure over a warm pad, one swell, one resolve.
Synthesized in numpy (no samples). Loudness is deliberately quiet and dynamic: it's a film, not a beat.
"""
import pathlib, subprocess, tempfile, wave, sys
import numpy as np
sys.path.insert(0, str(pathlib.Path(__file__).parent.parent / 'social' / 'instagram'))
import audio as A

SR = A.SR
N = lambda m: 440 * 2 ** ((m - 69) / 12)
CHORDS = [[47, 50, 54], [43, 47, 50], [38, 42, 45], [45, 49, 52]]   # Bm  G  D  A  (bass triads, MIDI)


def felt(freq, dur=3.0, amp=0.2):
    t = A.t_axis(dur)
    env = np.minimum(1, t / 0.008) * np.exp(-t / 0.9)
    s = np.zeros_like(t)
    for h, a, d in [(1, 1, 1.0), (2, .42, .55), (3, .18, .35), (4, .08, .25)]:
        s += a * np.sin(2 * np.pi * freq * h * t + 0.3 * h) * np.exp(-t * (1 - d) * 1.4)
    s += .12 * np.sin(2 * np.pi * freq * 1.003 * t)          # slight detune = warmth
    return amp * env * s


def pad_chord(dur, midis, amp=0.05, attack=2.5, release=2.5):
    t = A.t_axis(dur)
    out = np.zeros_like(t)
    for k, m in enumerate(midis):
        f = N(m)
        out += np.sin(2 * np.pi * f * t) + .5 * np.sin(2 * np.pi * f * 2.002 * t + k) + .25 * np.sin(2 * np.pi * f * .999 * t)
    env = np.minimum(1, t / attack) * np.minimum(1, (dur - t) / release)
    return amp * env * out / len(midis)


def build(dur, start, swell, peak, end):
    b = np.zeros((int(dur * SR), 2))
    for k, ch in enumerate(CHORDS * 20):                      # continuous pad
        at = k * 6.0
        if at >= dur: break
        A.place(b, pad_chord(min(7.5, dur - at), ch, 0.035), at, -0.2 if k % 2 else 0.2)
    step = .75; t = start; i = 0                              # felt-piano figure
    while t < peak - 0.2:
        ch = CHORDS[(int((t - start) // 6.0)) % 4]
        pat = [ch[0] + 24, ch[2] + 12, ch[1] + 24, ch[2] + 24, ch[0] + 36, ch[2] + 24, ch[1] + 24, ch[2] + 12]
        A.place(b, felt(N(pat[i % 8]), 3.2, .16 if i % 8 == 0 else .11), t, (i % 5 - 2) * .12)
        t += step; i += 1
    sw = max(0.5, peak - swell); tt = A.t_axis(sw + 1.0)      # swell into the peak
    for m in [50, 57, 62, 66, 69]:
        env = (np.clip(tt / sw, 0, 1) ** 2) * np.minimum(1, (sw + 1.0 - tt) / 1.0)
        A.place(b, 0.05 * env * (np.sin(2 * np.pi * N(m) * tt) + .4 * np.sin(2 * np.pi * N(m) * 2.003 * tt)), swell, 0)
    for m in [50, 57, 62, 66, 74]:                            # peak: full D major
        A.place(b, felt(N(m), 5.0, .15), peak, (m % 3 - 1) * .2)
    A.place(b, pad_chord(min(8.0, dur - peak), [38, 45, 50, 54, 57], 0.06, 0.4, 4.0), peak, 0)
    A.place(b, felt(N(86), 6.0, .11), end, 0.1)               # the last note, hanging
    A.place(b, felt(N(81), 6.0, .08), end + 0.7, -0.1)
    return b


def render(dur, start, swell, peak, end, out_wav):
    b = A.reverb(build(dur, start, swell, peak, end), 0.32)
    t = A.t_axis(dur)
    b *= (np.minimum(1, t / 1.5) * np.minimum(1, (dur - t) / 2.5))[:, None]
    b /= max(1e-9, np.abs(b).max()) / 0.8
    pcm = (np.clip(b, -1, 1) * 32767).astype('<i2')
    with wave.open(str(out_wav), 'wb') as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm.tobytes())


def mux(video, dur, cues):
    with tempfile.TemporaryDirectory() as d:
        wav = pathlib.Path(d) / 'a.wav'; render(dur, *cues, wav)
        tmp = pathlib.Path(d) / 'o.mp4'
        subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', str(video), '-i', str(wav), '-map', '0:v:0', '-map', '1:a:0', '-c:v', 'copy',
                        '-af', 'loudnorm=I=-18:TP=-2.5:LRA=14', '-c:a', 'aac', '-b:a', '192k', '-ar', '44100', '-movflags', '+faststart', '-shortest', str(tmp)], check=True)
        tmp.replace(video)
    print('score added:', pathlib.Path(video).name)
