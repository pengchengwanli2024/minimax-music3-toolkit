# MiniMax Music 3 Local Song Toolkit

[中文](README.md) | English

A thin toolchain for generating Chinese songs locally with **MiniMax Music 3** on **ComfyUI**: turn *lyrics + style caption* into a submittable API workflow, render several takes with different seeds, poll progress, pull the audio back, and render a waveform/spectrogram preview.

> Built and measured on Windows + ComfyUI Desktop. No third-party dependencies: PowerShell 5+/7 only, and Python uses the `av` / `numpy` / `Pillow` that already ship with a ComfyUI environment.

## Pipeline

```text
lyrics.txt + caption.txt
        │  scripts/build_prompt.ps1
        ▼
   prompt.json  ──POST /prompt──▶  ComfyUI  ──▶  AR text encoder → DiT sampler → VAE decode
        ▲                                              │
        │  scripts/generate.ps1 / run_batch.ps1        │ GET /history/{id}
        └──────────────────────────────────────────────┘
                       │ GET /view
                       ▼
                  out/*.mp3  ──scripts/make_audio_preview.py──▶  preview.png
```

## Requirements

- ComfyUI **≥ 0.43** (older builds lack the `MiniMaxMusic3TextEncode` node)
- GPU: works on a 16 GB laptop 4090 (fp16 DiT + int8 text encoder + tiled VAE decode)
- Models (≈13.5 GB) from [`Comfy-Org/MiniMax-Music-3`](https://huggingface.co/Comfy-Org/MiniMax-Music-3):

| Folder | File |
|---|---|
| `models/diffusion_models/` | `minimax_music3_dit_fp16.safetensors` (or the int8 variant for low VRAM) |
| `models/text_encoders/` | `minimax_music3_text_encoder_pruned_int8_convrot.safetensors` |
| `models/vae/` | `minimax_music3_dav.safetensors` |

## Quick start

```powershell
# 0) environment self-check (tells you exactly what is missing)
pwsh -File .\scripts\doctor.ps1

# 1) ComfyUI is running on http://127.0.0.1:8188
Invoke-RestMethod http://127.0.0.1:8188/system_stats

# 2) one-command 30 s test song
pwsh -File .\scripts\generate.ps1 `
  -LyricsFile .\examples\02-gufeng-yanyudu\歌词.txt `
  -CaptionFile .\examples\02-gufeng-yanyudu\caption.txt `
  -Duration 30 -Seed 8823105 -Prefix 'Audio/quickstart' -OutDir .\out

# 3) preview image (use the ComfyUI python interpreter)
python .\scripts\make_audio_preview.py .\out\<file>.mp3 .\out\preview.png
```

## Scripts

| Script | What it does |
|---|---|
| `scripts/build_prompt.ps1` | lyrics + caption → API workflow JSON (lyrics tags kept, leading `《title》` dropped) |
| `scripts/generate.ps1` | build → submit → poll → download audio into `-OutDir` |
| `scripts/generate_batch.ps1` | same, N seeds in one go (`-Seeds 111,222` or `-Count 3`) |
| `scripts/run_prompt.ps1` | submit an existing workflow JSON and download the result |
| `scripts/run_batch.ps1` | queue several workflows at once |
| `scripts/make_audio_preview.py` | waveform + spectrogram PNG of a rendered song |
| `scripts/doctor.ps1` | environment self-check: service, version, nodes, models, VRAM, queue |

## Examples

| Dir | Song | Style | Length |
|---|---|---|---|
| `examples/01-rnb-heartbreak` | 还没学会不想你 | Chinese R&B / neo-soul heartbreak ballad | 2:00 |
| `examples/02-gufeng-yanyudu` | 烟雨渡 | gufeng narrative (swordsman · Jiangnan · ten years) | 2:30 / v2 ≈ 2:51 |
| `examples/03-poprock-ganlu` | 赶路的人 | Chinese pop-rock (campus → career → looking back) | ≈3:02–3:17 |

Each example ships `歌词.txt` (lyrics), `caption.txt` (style prompt), `prompt.json` (ready-to-submit workflow) and `说明.md` (notes).

Rendered demo audio is attached to the [v1.0.0 release](https://github.com/pengchengwanli2024/minimax-music3-toolkit/releases/tag/v1.0.0) instead of being committed.

## How to write prompts and lyrics

See [docs/prompt-guide.md](docs/prompt-guide.md): the three-part caption formula (global → vocal → arrangement, plus an "avoid" line), section-tag rules, rhyme schemes per section, chorus-hook rules, the 30 s → seed A/B → full-length iteration loop, and parameter notes.

## Measured performance (RTX 4090 Laptop 16 GB)

| Target length | Wall time (warm) | AR encode → DiT sample → VAE decode |
|---|---|---|
| 20 s | 58 s | 25 s → 28 s → 4 s |
| 120 s | 197 s | 82 s → 102 s → 12 s |
| 150 s | 259 s | 107 s → 133 s → 15 s |
| 190 s | 260 s | 128 s → 160 s → 18 s |

First run after an install/driver change is much slower (kernel compilation + weight warm-up).

## Known gotchas

- `SaveAudioAdvanced` needs two **flat** keys in API prompts: `format: "mp3"` **and** `format.quality: "V0"`; a nested object fails with `Required input is missing: quality`.
- ComfyUI < 0.43 has no MiniMax Music nodes.
- 16 GB VRAM: keep `VAEDecodeAudioTiled` on (tile 1536 / overlap 64).
- Launching Comfy Desktop from a process that sets `ELECTRON_RUN_AS_NODE=1` makes it exit immediately; normal double-click is unaffected.

## License

Code, original lyrics and style captions: **MIT** — see [LICENSE](LICENSE).
Model weights (MiniMax / Comfy Org), ComfyUI itself and generated audio are **not** covered — see [NOTICE.md](NOTICE.md).

## Related

- [minimax-h3-comfyui-playbook](https://github.com/pengchengwanli2024/minimax-h3-comfyui-playbook) — a hands-on MiniMax H3 video generation playbook on the same 16 GB GPU: reproducible parameter sets, measured runtimes, gotchas.

