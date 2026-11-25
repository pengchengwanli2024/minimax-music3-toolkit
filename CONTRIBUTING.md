# Contributing

感谢愿意一起完善这个项目。改动建议走 PR，小改动（错别字、文档补充）也可以直接开 PR。

## 本地验证（提交前请跑一遍）

```powershell
# 1) PowerShell 语法
Get-ChildItem scripts\*.ps1 | ForEach-Object {
  $tokens = $null; $errs = $null
  [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$errs) | Out-Null
  if ($errs.Count) { throw "$($_.Name): $($errs[0].Message)" }
}

# 2) Python 语法
python -m py_compile scripts\make_audio_preview.py

# 3) 示例工作流结构与参数（离线单元测试，不需要 ComfyUI）
python -m unittest discover -s tests -v

# 4) 示例工作流 JSON 合法
python -c "import json,glob; [json.load(open(f,encoding='utf-8')) for f in glob.glob('examples/**/*.json',recursive=True)]; print('ok')"

# 5) Markdown 相对链接（图片/文档路径别写错层级）
python scripts\check_links.py

# 6) 端到端（需要本地 ComfyUI + 模型，约 1 分钟）
pwsh -File .\scripts\generate.ps1 -LyricsFile .\examples\01-rnb-heartbreak\歌词.txt `
  -CaptionFile .\examples\01-rnb-heartbreak\caption.txt -Duration 20 -Seed 1 -Prefix 'Audio/ci' -OutDir .\out
```

## 约定

- **只提交文本**：音频（`*.mp3/flac/wav`）、预览图、`out/` 不入库；示例音频放到 GitHub Release。
- **不要提交本机路径**：脚本里用参数或 `$PSScriptRoot`，不要写死用户目录、盘符路径这类本机绝对路径（CI 会检查）。
- **新示例放在 `examples/<NN-slug>/`**，至少包含 `歌词.txt`、`caption.txt`、`prompt.json`、`说明.md`。
- 提交信息用「类型: 简述」（`feat:` / `fix:` / `docs:` / `chore:`）。

## 报问题

用 Issue 模板，附上：ComfyUI 版本（`/system_stats`）、显卡与显存、`prompt.json` 里的关键参数、ComfyUI 日志里的 `Prompt executed` / 报错行。
