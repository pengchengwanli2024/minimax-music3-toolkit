# 部署与实测记录

## 1. 目标环境

| 项目 | 实测值 |
|---|---|
| ComfyUI | 0.43.0 起可用（实测期间升级到 0.46.0 仍正常），Comfy Desktop 独立版也可以 |
| GPU | RTX 4090 Laptop，16 GB VRAM |
| 内存 | 64 GB（模型加载期峰值占用较高，建议 ≥32 GB） |
| 推理环境 | ComfyUI 自带 `.venv`（Python 3.13、torch 2.12.1+cu130） |
| 操作系统 | Windows 11 |

低显存提示：DiT 用 int8 版（约 2.5 GB）可再省约 2 GB 显存；文本编码器只有 pruned int8 一个版本（8.57 GB），是显存和速度的主要瓶颈。

## 2. 模型落位

ComfyUI 会按 `models/<type>/` 及 `extra_model_paths.yaml` 注册的目录扫描模型，文件名必须与工作流里一致：

```
ComfyUI/
└── models/
    ├── diffusion_models/minimax_music3_dit_fp16.safetensors          (4.58 GiB)
    ├── text_encoders/minimax_music3_text_encoder_pruned_int8_convrot.safetensors  (8.57 GiB)
    └── vae/minimax_music3_dav.safetensors                            (0.20 GiB)
```

下载源：[`Comfy-Org/MiniMax-Music-3`](https://huggingface.co/Comfy-Org/MiniMax-Music-3)

- `diffusion_models/minimax_music3_dit_fp16.safetensors`（满血）
- `diffusion_models/minimax_music3_dit_int8_convrot.safetensors`（低显存可选）
- `text_encoders/minimax_music3_text_encoder_pruned_int8_convrot.safetensors`
- `vae/minimax_music3_dav.safetensors`

## 3. 验证清单

```powershell
# 1) 服务在线，版本 >= 0.43，能在 devices 里看到 CUDA 设备
Invoke-RestMethod http://127.0.0.1:8188/system_stats | ConvertTo-Json -Depth 4

# 2) 节点已注册（没有这一项说明版本太旧）
(Invoke-RestMethod http://127.0.0.1:8188/object_info).MiniMaxMusic3TextEncode

# 3) 三个模型都能被扫描到
foreach ($f in 'diffusion_models','text_encoders','vae') {
  (Invoke-RestMethod "http://127.0.0.1:8188/models/$f") | Select-String music3
}
```

## 4. 一次完整生成的时间线（ComfyUI 日志）

以 150 秒曲为例：

```
got prompt
Model storage policy: ... text_encoders/minimax_music3_text_encoder_pruned_int8_convrot.safetensors
CLIP/text encoder model load device: cuda:0, offload device: cpu, dtype: torch.float16
Model MiniMaxMusic3TEModel prepared for dynamic VRAM loading. 8758MB Staged.
AR sampling: 100%|...| 3750/3750 [01:47<00:00, 34.9it/s]     <- 文本编码器自回归，按 25 步/秒音频
model_type FLOW
Requested to load MiniMaxMusic3                                 <- DiT 采样
Model MiniMaxMusic3DAV ... loaded completely; 206.60 MB
Prompt executed in 259.16 seconds
```

耗时分布：**AR 采样（文本编码器）≈ 40%，DiT 采样 ≈ 50%，VAE 解码 ≈ 10%**。所以「提速」主要看文本编码器，换 int8 DiT 帮助有限。

## 5. 实测性能

| 目标时长 | 实际输出 | 总耗时（热态） |
|---|---|---|
| 20 s | 20.0 s | 58 s |
| 30 s | 30.0 s | 58 s |
| 120 s | 120.0 s | 197 s |
| 150 s | 150.0 s | 259 s |
| 190 s | 171–190 s | 296–345 s |

> 冷启动第一跑会明显更慢（内核编译 + 权重预热），例如同参数一次 20 秒曲子跑了 298 秒。跑过一两次之后恢复正常。

## 6. 常见问题

| 现象 | 原因 / 解决 |
|---|---|
| `Required input is missing: quality` | `SaveAudioAdvanced` 的动态下拉参数在 API 里是两个平铺键：`format: "mp3"` + `format.quality: "V0"`，不要写成嵌套对象 |
| 节点列表里没有 MiniMax Music | ComfyUI 低于 0.43，升级 |
| 长曲 OOM / 解码很慢 | 用工作流默认的 `VAEDecodeAudioTiled`（tile 1536 / overlap 64）；显存实在紧张把 tile 调小 |
| 生成时长比设定短 | 正常，模型会判断歌曲自然结束（实测 190 秒设定可能输出 171 秒） |
| Comfy Desktop 从脚本里启动即退出 | 父进程环境里带 `ELECTRON_RUN_AS_NODE=1` 时 Electron 会当 Node 运行后退出；正常双击启动不受影响 |
| `SaveAudioAdvanced` 输出 mp3 失败 | 实测 ComfyUI 自带 PyAV 可以编码 mp3 V0，无需系统 ffmpeg |

## 7. 可选：让 ComfyUI 常驻

Comfy Desktop 关了窗口服务也会停。要从命令行常驻启动 ComfyUI（Windows 示例，路径按自己环境改）：

```powershell
$install = "$env:LOCALAPPDATA\Comfy-Desktop\ComfyUI-Installs\ComfyUI"
$py = "$install\ComfyUI\.venv\Scripts\python.exe"
Start-Process -FilePath $py -WorkingDirectory $install -WindowStyle Minimized -ArgumentList @(
  '-s','ComfyUI\main.py','--enable-manager'
)
```

确认端口：`netstat -ano | findstr :8188`。
