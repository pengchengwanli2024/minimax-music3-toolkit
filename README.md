# MiniMax Music 3 本地创作工作台

[![CI](https://github.com/pengchengwanli2024/minimax-music3-toolkit/actions/workflows/ci.yml/badge.svg)](https://github.com/pengchengwanli2024/minimax-music3-toolkit/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/github/license/pengchengwanli2024/minimax-music3-toolkit)](LICENSE)
[![ComfyUI](https://img.shields.io/badge/ComfyUI-%E2%89%A5%200.43-4a4a4a)](https://github.com/comfyanonymous/ComfyUI)
[![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20PowerShell-blue)](#)

[English](README.en.md) | 中文

在本地 ComfyUI 上用 **MiniMax Music 3** 生成中文歌曲的一套轻量工具链：把「歌词 + 曲风描述」变成可直接提交的 API 工作流，批量出多版、自动轮询进度、拉回音频并生成波形/频谱预览图。

> 为 Windows + ComfyUI(Desktop) 实测环境编写，全部脚本无第三方依赖（PowerShell 5+ / PowerShell 7，Python 侧只用 ComfyUI 自带的 `av`、`numpy`、`Pillow`）。

```mermaid
flowchart LR
    A["歌词.txt<br/>caption.txt"] --> B["build_prompt.ps1"]
    B --> C["prompt.json"]
    C -->|"POST /prompt"| D["ComfyUI"]
    D -->|"GET /history/{id}<br/>轮询排队与进度"| E["完成"]
    E -->|"GET /view"| F["out/*.mp3"]
    F --> G["make_audio_preview.py"]
    G --> H["波形 + 频谱 PNG"]
```

**试听**：三首示例的成品音频挂在 [v1.0.0 Release](https://github.com/pengchengwanli2024/minimax-music3-toolkit/releases/tag/v1.0.0)（音频不入库，避免仓库变大）。

## 项目包含什么

| 目录 | 内容 |
|---|---|
| `scripts/build_prompt.ps1` | 把歌词 + caption 组装成 MiniMax Music 3 的 API 工作流 JSON |
| `scripts/generate.ps1` | 一条命令：组装 → 提交 → 轮询 → 下载成品音频 |
| `scripts/generate_batch.ps1` | 同词同风格批量出多版：`-Seeds 111,222` 或 `-Count 3`，支持 `-DryRun` |
| `scripts/run_prompt.ps1` | 提交已有工作流并等待结果、下载音频 |
| `scripts/run_batch.ps1` | 一次提交多份工作流（不同 seed/版本），排队跑完 |
| `scripts/make_audio_preview.py` | 生成波形 + 频谱预览图（PNG），用来快速检查一首歌的结构 |
| `examples/` | 三首已完成的中文原创示例（歌词 + caption + 工作流 JSON + 说明） |
| `docs/deployment.md` | 部署过程、模型清单、实测性能、踩过的坑 |
| `docs/prompt-guide.md` | 提示词三段式、押韵辙表、副歌钩子、参数与迭代流程 |
| `docs/images/` | 三首示例的波形 + 频谱预览图 |


## 环境要求

- Windows 10/11（脚本是 PowerShell）
- ComfyUI **≥ 0.43**（版本太低没有 `MiniMaxMusic3TextEncode` 节点）；Comfy Desktop 也可以
- 显卡：本地实测 RTX 4090 Laptop **16 GB VRAM** 可跑（fp16 DiT + int8 文本编码器 + tiled 解码）
- 磁盘：模型约 13.5 GB

### 需要的模型文件

来自 Hugging Face：[`Comfy-Org/MiniMax-Music-3`](https://huggingface.co/Comfy-Org/MiniMax-Music-3)

| 放到 ComfyUI | 文件 |
|---|---|
| `models/diffusion_models/` | `minimax_music3_dit_fp16.safetensors`（4.58 GiB，满血）；低显存可选 `minimax_music3_dit_int8_convrot.safetensors` |
| `models/text_encoders/` | `minimax_music3_text_encoder_pruned_int8_convrot.safetensors`（8.57 GiB，必需） |
| `models/vae/` | `minimax_music3_dav.safetensors`（0.20 GiB） |

> 模型可以放在统一模型库（ComfyUI 的 `extra_model_paths.yaml` 里注册的目录），脚本只按文件名提交，不关心物理路径。

## 快速开始

1. **启动 ComfyUI**，确认面板地址（默认 `http://127.0.0.1:8188`）：

   ```powershell
   Invoke-RestMethod http://127.0.0.1:8188/system_stats
   ```

2. **确认模型已就位**（应能列出 3 个 music3 文件）：

   ```powershell
   (Invoke-RestMethod http://127.0.0.1:8188/models/diffusion_models) | Select-String music3
   ```

3. **生成一首 30 秒测试曲**（用仓库自带示例）：

   ```powershell
   pwsh -File .\scripts\generate.ps1 `
     -LyricsFile .\examples\02-gufeng-yanyudu\歌词.txt `
     -CaptionFile .\examples\02-gufeng-yanyudu\caption.txt `
     -Duration 30 -Seed 8823105 -Prefix 'Audio/quickstart' -OutDir .\out
   ```

   结束后 `out\` 里会有音频；再生成预览图：

   ```powershell
   python .\scripts\make_audio_preview.py .\out\<文件名>.mp3 .\out\preview.png
   ```

   （`python` 用 ComfyUI 的虚拟环境解释器，里面有 `av/numpy/Pillow`）

## 脚本用法

### `build_prompt.ps1` —— 只生成工作流

```powershell
.\scripts\build_prompt.ps1 -LyricsFile .\lyrics.txt -CaptionFile .\caption.txt `
  -OutFile .\prompt.json -Duration 150 -Seed 8823105 -Prefix 'Audio/mysong'
```

参数：`-Duration` 目标时长（秒，模型上限约 300，可能提前自然结束）、`-Seed`、`-Steps`(默认 30)、`-CfgScale`(1.7)、`-TopK`(50)，以及模型文件名 `-UnetName/-ClipName/-VaeName`。

歌词文件支持 `[Intro] [Verse] [Pre-Chorus] [Chorus] [Bridge] [Outro]` 段落标签；首行如果是 `《歌名》` 会被自动忽略，只把标签和歌词送进模型。

### `generate.ps1` —— 一条命令出成品

在 `build_prompt.ps1` 的基础上提交任务、轮询 `/history`，成功后通过 `/view` 把音频下载到 `-OutDir`。

```powershell
.\scripts\generate.ps1 -LyricsFile .\歌词.txt -CaptionFile .\caption.txt `
  -Duration 190 -Seed 8823111 -Prefix 'Audio/yanyudu_A' -OutDir .\out
```

### `generate_batch.ps1` —— 同词同风格批量出多版

```powershell
# 指定 seed 列表（两个版本）
.\scripts\generate_batch.ps1 -LyricsFile .\歌词.txt -CaptionFile .\caption.txt `
  -Seeds 8823111,8823112 -Duration 190 -Prefix 'Audio/yanyudu' -OutDir .\out

# 或者随机出 3 版
.\scripts\generate_batch.ps1 -LyricsFile .\歌词.txt -CaptionFile .\caption.txt -Count 3 -Duration 190

# 只生成工作流、不提交（先检查参数）
.\scripts\generate_batch.ps1 -LyricsFile .\歌词.txt -CaptionFile .\caption.txt -Seeds 111,222 -DryRun
```

> 注意：`pwsh -File` 会把 `-Seeds 111,222` 当成一个字符串传入，脚本内部会按逗号/空格拆分，所以两种调用方式都可用。

### `run_prompt.ps1` / `run_batch.ps1` —— 已有工作流

```powershell
.\scripts\run_prompt.ps1 -PromptFile .\prompt.json -OutDir .\out
.\scripts\run_batch.ps1 -PromptFiles .\a.json,.\b.json -OutDir .\out
```

批量脚本就是常见的「同一份词曲、不同 seed」用法：多出两版挑演唱。实测一次排两版（各 3 分钟歌）约 11 分钟。

## 写作指南（实测有效）

> 更完整的版本见 **[docs/prompt-guide.md](docs/prompt-guide.md)**：caption 三段式逐项示例、六组押韵辙对照表、副歌钩子四条规则、30 秒→seed A/B→整曲的迭代流程、参数影响。

**Caption（曲风描述）写三段**：全局信息（曲风/年代/BPM/调性）→ 人声细节（性别、音色、唱法、情绪）→ 编曲结构（乐器、段落动态、制作质感），最后加一句 `Avoid ...` 排除不想要的东西。英文写，模型对英文描述更稳。

**歌词**用段落标签控制结构，标签是唯一可执行的指令，正文只表达情绪。同一段压一个韵辙、副歌四句一个钩子、重复三遍，是"好记"最有效的手段。

**时长与成本**：目标时长按字数估，约 25 个音节/秒的 token 速率；实测 30 秒曲约 1 分钟、2 分钟曲约 3~5 分钟、3 分钟曲约 5~6 分钟（4090 Laptop 16G）。

## 实测性能（RTX 4090 Laptop 16 GB / ComfyUI 0.43–0.46）

| 目标时长 | 实际耗时 | 分段（AR 文本编码 → DiT 采样 → VAE 解码） |
|---|---|---|
| 20 s | 58 s（热态首测 298 s，冷启动含内核编译） | 25 s → 28 s → 4 s |
| 120 s | 197 s | 82 s → 102 s → 12 s |
| 150 s | 259 s | 107 s → 133 s → 15 s |
| 190 s | 260 s | 128 s → 160 s → 18 s |

> 冷启动（第一次跑、换了驱动/内核后）明显更慢，第二次起恢复正常。

## 踩过的坑

- **`SaveAudioAdvanced` 的动态下拉参数在 API 里是两个平铺键**：`format: "mp3"` + `format.quality: "V0"`（不是嵌套对象），否则报 `Required input is missing: quality`。本仓库的 `build_prompt.ps1` 已经处理。
- **ComfyUI 版本 < 0.43 没有 MiniMax Music 节点**，务必升级。
- **刚从 Agent 会话里启动 Comfy Desktop 会被 `ELECTRON_RUN_AS_NODE=1` 影响**，Electron 客户端启动即退出；正常双击不受影响。
- **16 GB 显存要开 tiled VAE 解码**（工作流默认 `VAEDecodeAudioTiled`，tile 1536/overlap 64），否则长曲目解码可能 OOM。
- 长曲目（>4 分钟）建议先跑 60 秒确认 prompt 方向，再一次性出全曲。

## 示例歌曲（`examples/`）

| 目录 | 歌名 | 风格 | 时长 | 波形预览 |
|---|---|---|---|---|
| `01-rnb-heartbreak` | 还没学会不想你 | 中文 R&B / neo-soul 失恋抒情 | 2:00 | [预览](docs/images/rnb-heartbreak.png) |
| `02-gufeng-yanyudu` | 烟雨渡 | 古风叙事（侠客·江南·十年重逢） | 2:30 / v2 约 2:51 | [预览](docs/images/gufeng-yanyudu-v2.png) |
| `03-poprock-ganlu` | 赶路的人 | 中文流行摇滚（校园→打拼→回望） | 约 3:02–3:17 | [预览](docs/images/poprock-ganlu.png) |

每首示例包含：`歌词.txt`、`caption.txt`（曲风描述）、`prompt.json`（可直接提交的工作流）、`说明.md`。

音频成品在 [v1.0.0 Release](https://github.com/pengchengwanli2024/minimax-music3-toolkit/releases/tag/v1.0.0) 提供试听；仓库本身只入库波形预览图（`docs/images/`），音频与 `out/` 目录都在 `.gitignore` 里，请用脚本自己生成。

## 声明与许可

- 脚本代码、`examples/` 中的原创歌词与曲风描述：**MIT**，见 [LICENSE](LICENSE)。
- 模型权重（归 MiniMax / Comfy Org）、ComfyUI 本体、生成音频的使用条款，以及风格参考的边界：见 [NOTICE.md](NOTICE.md)。
- 贡献代码/示例请先看 [CONTRIBUTING.md](CONTRIBUTING.md)；问题请用 Issue 模板（会自动带上 ComfyUI 版本、显卡、日志等字段）。

## 相关项目

- [minimax-h3-comfyui-playbook](https://github.com/pengchengwanli2024/minimax-h3-comfyui-playbook) —— 同一台 16 GB 显卡上的 MiniMax H3 视频生成实战手册：可复现的参数组合、实测耗时与踩坑清单

