param(
    [string]$BaseUrl = 'http://127.0.0.1:8188',
    [string]$DitName = 'minimax_music3_dit_fp16.safetensors',
    [string]$DitInt8Name = 'minimax_music3_dit_int8_convrot.safetensors',
    [string]$ClipName = 'minimax_music3_text_encoder_pruned_int8_convrot.safetensors',
    [string]$VaeName = 'minimax_music3_dav.safetensors'
)
$ErrorActionPreference = 'Stop'

$fail = 0
function Ok($msg)   { Write-Host ("  [ OK ] " + $msg) -ForegroundColor Green }
function Warn($msg) { Write-Host ("  [WARN] " + $msg) -ForegroundColor Yellow }
function Bad($msg)  { Write-Host ("  [FAIL] " + $msg) -ForegroundColor Red; $script:fail++ }

Write-Host "ComfyUI doctor - $BaseUrl"

# 1. service + version + device
$stats = $null
try {
    $stats = Invoke-RestMethod -Uri "$BaseUrl/system_stats" -TimeoutSec 10
    Ok ("ComfyUI {0} is reachable" -f $stats.system.comfyui_version)
} catch {
    Bad ("cannot reach $BaseUrl/system_stats - is ComfyUI running? ($($_.Exception.Message))")
}

if ($stats) {
    $verText = [string]$stats.system.comfyui_version
    $parts = $verText -split '\.'
    $major = 0; $minor = 0
    [void][int]::TryParse($parts[0], [ref]$major)
    if ($parts.Count -gt 1) { [void][int]::TryParse(($parts[1] -replace '\D.*', ''), [ref]$minor) }
    if ($major -gt 0 -or $minor -ge 43) { Ok ("version $verText >= 0.43") } else { Bad ("version $verText is too old; MiniMax Music needs ComfyUI >= 0.43") }

    $dev = $stats.devices | Select-Object -First 1
    if ($dev) {
        $vram = if ($dev.vram_total) { [math]::Round($dev.vram_total / 1MB) } else { 0 }
        $free = if ($dev.vram_free) { [math]::Round($dev.vram_free / 1MB) } else { 0 }
        Ok ("device: {0} (VRAM {1} MB total / {2} MB free)" -f $dev.name, $vram, $free)
        if ($vram -gt 0 -and $vram -lt 12000) { Warn ("VRAM below 12 GB - use the int8 DiT and keep tiled VAE decode on") }
    } else {
        Warn 'no CUDA device reported by /system_stats'
    }
    Write-Host ("  [info] python {0} / torch {1}" -f $stats.system.python_version, $stats.system.pytorch_version)
}

# 2. nodes
if ($stats) {
    try {
        $oi = Invoke-RestMethod -Uri "$BaseUrl/object_info" -TimeoutSec 60
        foreach ($node in 'MiniMaxMusic3TextEncode', 'EmptyMiniMaxMusic3LatentAudio', 'SaveAudioAdvanced', 'VAEDecodeAudioTiled') {
            if ($oi.PSObject.Properties.Name -contains $node) { Ok ("node registered: $node") } else { Bad ("node missing: $node (ComfyUI too old?)") }
        }
    } catch {
        Bad ("cannot read /object_info: $($_.Exception.Message)")
    }

    # 3. model files (by file name, wherever they are registered)
    $required = @{
        diffusion_models = @($DitName, $DitInt8Name)
        text_encoders    = @($ClipName)
        vae              = @($VaeName)
    }
    foreach ($folder in $required.Keys) {
        # NOTE: wrap explicitly - `@(Invoke-RestMethod ...)` inside try/catch can return a nested array
        $raw = $null
        try { $raw = Invoke-RestMethod -Uri "$BaseUrl/models/$folder" -TimeoutSec 20 } catch { }
        $names = @()
        foreach ($item in $raw) { $names += [string]$item }
        foreach ($want in $required[$folder]) {
            if ($names -contains $want) { Ok ("model found: $folder/$want") }
            else {
                if ($folder -eq 'diffusion_models') { Write-Host ("  [info] not found: $folder/$want") }
                else { Bad ("model missing: $folder/$want") }
            }
        }
        if ($folder -eq 'diffusion_models') {
            $hasAny = $false
            foreach ($want in $required[$folder]) { if ($names -contains $want) { $hasAny = $true } }
            if (-not $hasAny) { Bad ("no DiT found in $folder (expected one of: " + ($required[$folder] -join ', ') + ")") }
        }
    }

    # 4. queue
    try {
        $q = Invoke-RestMethod -Uri "$BaseUrl/queue" -TimeoutSec 20
        Write-Host ("  [info] queue: running={0} pending={1}" -f @($q.queue_running).Count, @($q.queue_pending).Count)
    } catch { Warn 'cannot read /queue' }
}

Write-Host ''
if ($fail -gt 0) {
    Write-Host ("FAILED: {0} check(s) did not pass. See README / docs/deployment.md." -f $fail) -ForegroundColor Red
    exit 1
}
Write-Host 'All checks passed - ready to generate.' -ForegroundColor Green
exit 0
