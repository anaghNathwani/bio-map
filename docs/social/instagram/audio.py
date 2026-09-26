"""Original, synthesized sound design for the BirdMap Reels (no samples, no licensing).

Each reel gets a soft pad, a pluck on every scene change, and a few stylized bird-like chirps.
The chirps are synthesized whistles, not recordings of real birds.
Timings match the scene times in build.py. `python3 build.py audio` re-muxes audio into the existing MP4s.
"""
import pathlib, subprocess, tempfile, wave
import numpy as np

SR = 44100
rng = np.random.default_rng(7)


def t_axis(dur): return np.arange(int(dur * SR)) / SR


def place(buf, sig, at, pan=0.0):
    i = int(at * SR)
    if i >= buf.shape[0]: return
    n = min(len(sig), buf.shape[0] - i)
    l, r = np.cos((pan + 1) * np.pi / 4), np.sin((pan + 1) * np.pi / 4)
    buf[i:i + n, 0] += sig[:n] * l
    buf[i:i + n, 1] += sig[:n] * r


def pluck(freq, dur=1.1, amp=0.22):
    t = t_axis(dur)
    env = np.minimum(1, t / 0.006) * np.exp(-t / 0.22)
    s = np.sin(2 * np.pi * freq * t) + 0.32 * np.sin(2 * np.pi * freq * 2 * t) * np.exp(-t / 0.10) + 0.10 * np.sin(2 * np.pi * freq * 3 * t) * np.exp(-t / 0.06)
    return amp * env * s


def chirp(f0, f1, dur=0.14, amp=0.10, vib=35.0, depth=90.0):
    t = t_axis(dur)
    f = f0 + (f1 - f0) * (t / dur) ** 1.4 + depth * np.sin(2 * np.pi * vib * t)
    ph = 2 * np.pi * np.cumsum(f) / SR
    env = np.sin(np.pi * t / dur) ** 2
    return amp * env * (np.sin(ph) + 0.15 * np.sin(2 * ph))


def phrase(start, notes, buf, amp=0.10, pan=0.0):
    """notes: [(f0, f1, dur, gap)] played one after another from `start`."""
    at = start
    for f0, f1, d, gap in notes:
        place(buf, chirp(f0, f1, d, amp), at, pan)
        at += d + gap


def pad(dur, freqs, amp=0.035):
    t = t_axis(dur)
    out = np.zeros_like(t)
    for k, f in enumerate(freqs):
        trem = 0.75 + 0.25 * np.sin(2 * np.pi * (0.11 + 0.03 * k) * t + k)
        out += np.sin(2 * np.pi * f * t) * trem + 0.4 * np.sin(2 * np.pi * f * 2.003 * t) * trem
    env = np.minimum(1, t / 1.6) * np.minimum(1, (dur - t) / 1.8)
    return amp * env * out / len(freqs)


def wind(dur, amp, until=None):
    n = rng.standard_normal(int(dur * SR))
    k = np.ones(400) / 400
    lo = np.convolve(n, k, mode='same')
    t = t_axis(dur)
    sweep = 0.6 + 0.4 * np.sin(2 * np.pi * 0.35 * t)
    fade = np.ones_like(t) if until is None else np.clip((until - t) / 1.2, 0, 1)
    return amp * lo * sweep * fade * 6


def ping(freq, dur=1.6, amp=0.10):
    t = t_axis(dur)
    return amp * np.exp(-t / 0.35) * np.sin(2 * np.pi * freq * t) * np.minimum(1, t / 0.004)


def glide(f0, f1, dur, amp=0.07):
    t = t_axis(dur)
    f = f0 + (f1 - f0) * (t / dur)
    env = np.minimum(1, t / 0.15) * np.minimum(1, (dur - t) / 0.25)
    return amp * env * np.sin(2 * np.pi * np.cumsum(f) / SR)


def reverb(x, wet=0.22):
    n = int(1.4 * SR)
    ir = rng.standard_normal((n, 2)) * np.exp(-np.arange(n) / (0.32 * SR))[:, None]
    ir /= np.abs(ir).sum(axis=0) + 1e-9
    L = len(x) + n
    size = 1 << (L - 1).bit_length()
    y = np.stack([np.fft.irfft(np.fft.rfft(x[:, c], size) * np.fft.rfft(ir[:, c], size), size)[:len(x)] for c in range(2)], axis=1)
    return x * (1 - wet) + y * wet * 4


A3, C4, E4, G4, A4, B4, C5, D5, E5, G5, A5, C6, E6 = 220, 261.63, 329.63, 392, 440, 493.88, 523.25, 587.33, 659.25, 783.99, 880, 1046.5, 1318.5
CH = lambda a, b, d=0.13, g=0.05: (a, b, d, g)


def reel_how(dur):
    b = np.zeros((int(dur * SR), 2))
    b[:, 0] += (p := pad(dur, [A3, E4, B4])); b[:, 1] += p
    for at, f in [(0.3, E5), (3.5, G5), (7.2, A5), (10.9, C6)]: place(b, pluck(f), at, 0.0)
    place(b, pluck(A5, 2.2, 0.18), 14.2); place(b, pluck(E6, 2.2, 0.12), 14.25)
    phrase(1.0, [CH(3000, 4200), CH(3600, 4600), CH(3200, 3900, .18)], b, 0.09, -0.4)
    phrase(5.6, [CH(3300, 4400), CH(3900, 3000, .2)], b, 0.08, 0.5)
    phrase(9.0, [CH(2800, 4000), CH(3500, 4500), CH(3000, 3600)], b, 0.08, -0.3)
    phrase(12.4, [CH(3400, 4600), CH(4200, 3200, .2)], b, 0.08, 0.4)
    return b


def reel_tips(dur):
    b = np.zeros((int(dur * SR), 2))
    b[:, 0] += (p := pad(dur, [A3, E4, A4], 0.03)); b[:, 1] += p
    w = wind(dur, 0.05, until=8.6)  # tip 2 is "keep wind out": the wind bed drops away
    b[:, 0] += w; b[:, 1] += np.roll(w, 900)
    for at, f in [(0.5, E5), (3.2, G5), (6.6, A5), (10.0, C6)]: place(b, pluck(f, 1.0, 0.18), at)
    place(b, pluck(A5, 2.2, 0.16), 13.2); place(b, pluck(E6, 2.2, 0.10), 13.25)
    phrase(1.2, [CH(3000, 4200), CH(3600, 4600)], b, 0.08, -0.4)
    phrase(3.9, [CH(3200, 4400), CH(3800, 4700), CH(3400, 4000, .16)], b, 0.11, -0.2)   # tip 1: get close (louder)
    phrase(7.2, [CH(3000, 4300), CH(3700, 4900)], b, 0.10, 0.3)                        # tip 2: wind fading
    phrase(8.9, [CH(3100, 4400), CH(3800, 4800), CH(3300, 4100, .16)], b, 0.12, 0.0)   # clean call once wind is gone
    phrase(10.5, [CH(3400, 4700), CH(4300, 3300, .22)], b, 0.12, 0.2)                   # tip 3: short and clean
    return b


def reel_ondevice(dur):
    b = np.zeros((int(dur * SR), 2))
    b[:, 0] += (p := pad(dur, [A3, E4, C5], 0.03)); b[:, 1] += p
    place(b, pluck(E5), 0.5); place(b, pluck(G5), 3.2); place(b, pluck(A5), 7.2)
    for k in range(4): place(b, ping(880 if k % 2 == 0 else 660, 1.6, 0.09), 4.0 + 1.6 * k)  # matches the pulse ring
    place(b, glide(700, 250, 0.7, 0.06), 7.9)                                                 # the strike through the cloud
    place(b, pluck(A5, 2.2, 0.16), 10.5); place(b, pluck(E6, 2.2, 0.10), 10.55)
    phrase(11.6, [CH(3300, 4500), CH(3900, 3100, .2)], b, 0.07, 0.3)
    return b


def reel_unsure(dur):
    b = np.zeros((int(dur * SR), 2))
    b[:, 0] += (p := pad(dur, [A3, E4, G4], 0.03)); b[:, 1] += p
    place(b, pluck(E5), 0.2); place(b, pluck(A5), 3.1)
    place(b, glide(300, 520, 1.6, 0.06), 6.0)              # confidence filling
    place(b, pluck(D5 / 2, 1.6, 0.20), 7.7)                # settles below the bar
    place(b, pluck(A5, 2.2, 0.16), 9.5); place(b, pluck(E6, 2.2, 0.10), 9.55)
    phrase(10.6, [CH(3300, 4500), CH(3900, 3100, .2)], b, 0.07, -0.3)
    return b


BUILDERS = {'01-how-birdmap-works': reel_how, '02-tips-bird-sound': reel_tips, '03-stays-on-your-phone': reel_ondevice, '04-says-when-unsure': reel_unsure}


def render_wav(name, dur, out):
    b = BUILDERS[name](dur)
    b = reverb(b, 0.22)
    t = t_axis(dur)
    b *= (np.minimum(1, t / 0.25) * np.minimum(1, (dur - t) / 0.9))[:, None]
    b /= max(1e-9, np.abs(b).max()) / 0.7
    pcm = (np.clip(b, -1, 1) * 32767).astype('<i2')
    with wave.open(str(out), 'wb') as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm.tobytes())


def duration(mp4):
    r = subprocess.run(['ffprobe', '-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', str(mp4)], capture_output=True, text=True, check=True)
    return float(r.stdout.strip())


def add_audio(mp4):
    """Replace/attach the audio track of an existing reel (the video stream is copied untouched)."""
    mp4 = pathlib.Path(mp4)
    name = mp4.stem
    dur = duration(mp4)
    with tempfile.TemporaryDirectory() as d:
        wav = pathlib.Path(d) / 'a.wav'
        render_wav(name, dur, wav)
        tmp = pathlib.Path(d) / 'out.mp4'
        subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', str(mp4), '-i', str(wav), '-map', '0:v:0', '-map', '1:a:0',
                        '-c:v', 'copy', '-af', 'loudnorm=I=-16:TP=-2.5:LRA=7', '-c:a', 'aac', '-b:a', '192k', '-ar', '44100',
                        '-movflags', '+faststart', '-shortest', str(tmp)], check=True)
        tmp.replace(mp4)
    print('audio added:', mp4.name)
