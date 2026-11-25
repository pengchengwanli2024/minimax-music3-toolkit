param(
    [Parameter(Mandatory = $true)][string]$LyricsFile,
    [Parameter(Mandatory = $true)][string]$CaptionFile,
    [Parameter(Mandatory = $true)][string]$OutFile,
    [double]$Duration = 120.0,
    [long]$Seed = 8823001,
    [string]$Prefix = 'Audio/song',
    [int]$Steps = 30,
    [double]$CfgScale = 1.7,
    [int]$TopK = 50,
    [string]$UnetName = 'minimax_music3_dit_fp16.safetensors',
    [string]$ClipName = 'minimax_music3_text_encoder_pruned_int8_convrot.safetensors',
    [string]$VaeName = 'minimax_music3_dav.safetensors'
)
$ErrorActionPreference = 'Stop'

if (-not (Test-Path $LyricsFile)) { throw "LyricsFile not found: $LyricsFile" }
if (-not (Test-Path $CaptionFile)) { throw "CaptionFile not found: $CaptionFile" }

$lyrics = (Get-Content $LyricsFile -Raw) -replace "`r`n", "`n"
$caption = (Get-Content $CaptionFile -Raw) -replace "`r`n", "`n"
$lyrics = $lyrics.TrimEnd()
$caption = $caption.TrimEnd()

# Drop a leading title line such as 《song name》; the model only wants section tags + lyric text.
$lines = $lyrics -split "`n"
$first = 0
while ($first -lt $lines.Count -and $lines[$first].Trim() -eq '') { $first++ }
if ($first -lt $lines.Count -and $lines[$first].Trim() -match '^《.+》$') {
    $lyrics = (($lines[($first + 1)..($lines.Count - 1)]) -join "`n").Trim()
}
if (-not $lyrics) { throw "Lyrics is empty after stripping the title line: $LyricsFile" }

$prompt = [ordered]@{
    '3'  = @{ class_type = 'CLIPLoader'; inputs = @{ clip_name = $ClipName; type = 'minimax'; device = 'default' } }
    '6'  = @{ class_type = 'UNETLoader'; inputs = @{ unet_name = $UnetName; weight_dtype = 'default' } }
    '7'  = @{ class_type = 'VAELoader'; inputs = @{ vae_name = $VaeName } }
    '38' = @{ class_type = 'SeedNode'; inputs = @{ seed = $Seed } }
    '13' = @{ class_type = 'MiniMaxMusic3TextEncode'; inputs = @{
            clip         = @('3', 0)
            caption      = $caption
            lyrics       = $lyrics
            seed         = @('38', 0)
            max_duration = $Duration
            cfg_scale    = $CfgScale
            top_k        = $TopK
        } }
    '10' = @{ class_type = 'ConditioningZeroOut'; inputs = @{ conditioning = @('13', 0) } }
    '15' = @{ class_type = 'EmptyMiniMaxMusic3LatentAudio'; inputs = @{ seconds = @('13', 1); batch_size = 1 } }
    '9'  = @{ class_type = 'KSampler'; inputs = @{
            model        = @('6', 0)
            seed         = @('38', 0)
            steps        = $Steps
            cfg          = $CfgScale
            sampler_name = 'euler'
            scheduler    = 'simple'
            positive     = @('13', 0)
            negative     = @('10', 0)
            latent_image = @('15', 0)
            denoise      = 1.0
        } }
    '42' = @{ class_type = 'VAEDecodeAudioTiled'; inputs = @{ samples = @('9', 0); vae = @('7', 0); tile_size = 1536; overlap = 64 } }
    '44' = @{ class_type = 'SaveAudioAdvanced'; inputs = @{
            audio            = @('42', 0)
            filename_prefix  = $Prefix
            format           = 'mp3'
            'format.quality' = 'V0'
        } }
}

$outDir = Split-Path -Parent $OutFile
if ($outDir -and -not (Test-Path $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }

$json = $prompt | ConvertTo-Json -Depth 20
Set-Content -Path $OutFile -Value $json -Encoding UTF8
Write-Host ("wrote {0} (lyrics {1} chars, caption {2} chars, duration {3}s, seed {4})" -f $OutFile, $lyrics.Length, $caption.Length, $Duration, $Seed)
