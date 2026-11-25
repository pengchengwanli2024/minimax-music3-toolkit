"""Render a quick waveform + spectrogram preview PNG for a generated song.

Usage:
    python make_audio_preview.py <input.mp3|flac|wav> <output.png>

Requires: av, numpy, Pillow  (all bundled in a ComfyUI/standalone environment).
"""
import sys
import numpy as np
import av
from PIL import Image, ImageDraw

if len(sys.argv) < 3:
    print(__doc__)
    sys.exit(1)

src = sys.argv[1]
out = sys.argv[2]

with av.open(src) as c:
    st = c.streams.audio[0]
    chunks = [f.to_ndarray() for f in c.decode(st)]
    sr = st.codec_context.sample_rate
a = np.concatenate(chunks, axis=1).astype(np.float32)  # (ch, n)
mono = a.mean(axis=0)
dur = len(mono) / sr

W, H = 1400, 640
wave_h = 260
spec_h = H - wave_h - 90
pad = 40

img = Image.new("RGB", (W, H), (16, 18, 24))
d = ImageDraw.Draw(img)

# ---- waveform ----
cols = W - 2 * pad
step = max(1, len(mono) // cols)
env_max, env_min = [], []
for i in range(cols):
    seg = mono[i * step:(i + 1) * step]
    if len(seg) == 0:
        env_max.append(0.0); env_min.append(0.0)
    else:
        env_max.append(float(seg.max())); env_min.append(float(seg.min()))
mid = 60 + wave_h // 2
scale = (wave_h / 2 - 8) / max(0.05, max(abs(x) for x in env_max + env_min))
for i in range(cols):
    x = pad + i
    y1 = mid - env_max[i] * scale
    y2 = mid - env_min[i] * scale
    d.line([(x, y1), (x, y2)], fill=(64, 224, 190), width=1)
d.line([(pad, mid), (W - pad, mid)], fill=(50, 56, 70), width=1)

# ---- spectrogram ----
win, hop = 1024, 256
n_frames = max(1, (len(mono) - win) // hop)
frames = np.lib.stride_tricks.sliding_window_view(mono, win)[::hop][:n_frames]
window = np.hanning(win).astype(np.float32)
spec = np.abs(np.fft.rfft(frames * window, axis=1))  # (frames, bins)
spec = spec[:, : win // 8]  # keep low half of the audible range
db = 20 * np.log10(spec.T + 1e-8)  # (bins, frames)
db = np.clip((db - db.max() + 80) / 80, 0, 1)  # 80 dB dynamic range

# simple viridis-like colormap
stops = np.array([
    [0.267, 0.005, 0.329],
    [0.283, 0.141, 0.458],
    [0.254, 0.265, 0.530],
    [0.207, 0.372, 0.553],
    [0.164, 0.471, 0.558],
    [0.128, 0.567, 0.551],
    [0.135, 0.659, 0.518],
    [0.267, 0.749, 0.441],
    [0.478, 0.821, 0.318],
    [0.741, 0.873, 0.150],
    [0.993, 0.906, 0.144],
])
idx = db * (len(stops) - 1)
lo = np.floor(idx).astype(int)
hi = np.minimum(lo + 1, len(stops) - 1)
frac = (idx - lo)[..., None]
rgb = (stops[lo] * (1 - frac) + stops[hi] * frac) * 255
spec_img = Image.fromarray(rgb[::-1].astype(np.uint8), "RGB").resize((cols, spec_h), Image.BILINEAR)
img.paste(spec_img, (pad, wave_h + 70))

# ---- labels ----
d.text((pad, 16), "MiniMax Music 3 - local test render", fill=(230, 235, 245))
d.text((pad, 34), f"{dur:.2f}s | 44.1 kHz stereo | mp3 V0 | ComfyUI 0.43.0 / RTX 4090 Laptop 16GB",
       fill=(140, 150, 170))
d.text((pad, wave_h + 50), "waveform", fill=(120, 130, 150))
d.text((pad, H - 20), "spectrogram (0-5.5 kHz)", fill=(120, 130, 150))
img.save(out)
print("saved", out, img.size)
