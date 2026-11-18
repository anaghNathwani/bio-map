"""Narration for the "Look up." films, synthesized locally with Kokoro (Apache-2.0 neural TTS, kokoro-onnx).

Each spoken line is cached as a WAV in vo/lines/. To use a HUMAN voice instead, record each line and drop the files
in over the same names (24 kHz or 44.1 kHz mono/stereo WAV, any length), then re-run the build: timing follows the files.

Model files live outside the repo:  ~/.cache/birdmap-tts/kokoro-v1.0.onnx  and  voices-v1.0.bin
(from https://github.com/thewh1teagle/kokoro-onnx/releases/tag/model-files-v1.0)
"""
import hashlib, pathlib, re
import numpy as np
import soundfile as sf

HERE = pathlib.Path(__file__).parent
LINES = HERE / 'vo' / 'lines'
CACHE = pathlib.Path.home() / '.cache' / 'birdmap-tts'
VOICE = 'qwen3-soft-v1'
REF_TEXT = 'The world keeps a diary. You are its handwriting.'
SPEED = 0.80          # slow, close, unhurried
_k = None


def slug(text):
    return re.sub(r'[^a-z0-9]+', '-', text.lower()).strip('-')[:48] + '-' + hashlib.md5(f'{VOICE}{SPEED}{text}'.encode()).hexdigest()[:6]


def synth(text):
    """Returns (path, samples float32 mono, sample_rate). Cached on disk."""
    global _k
    LINES.mkdir(parents=True, exist_ok=True)
    p = LINES / f'{slug(text)}.wav'
    if not p.exists():
        if _k is None:
            from mlx_audio.tts.utils import load_model
            _k = load_model(str(CACHE / 'qwen3-base'))
        r = list(_k.generate(text=text, ref_audio=str(HERE / 'vo' / 'ref-voice.wav'), ref_text=REF_TEXT, lang_code='english'))
        s, sr = np.concatenate([np.array(x.audio).astype('float32') for x in r]), _k.sample_rate
        sf.write(str(p), s.astype('float32'), sr)
    s, sr = sf.read(str(p), dtype='float32')
    if s.ndim > 1: s = s.mean(axis=1)
    return p, s, sr


def duration(text):
    _, s, sr = synth(text)
    return len(s) / sr
