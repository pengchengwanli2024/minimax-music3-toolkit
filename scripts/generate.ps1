param(
    [Parameter(Mandatory = $true)][string]$LyricsFile,
    [Parameter(Mandatory = $true)][string]$CaptionFile,
    [string]$OutDir = './out',
    [double]$Duration = 120.0,
    [long]$Seed = 0,
    [string]$Prefix = 'Audio/song',
    [int]$Steps = 30,
    [double]$CfgScale = 1.7,
    [int]$TopK = 50,
    [ValidateSet('V0', '128k', '320k')][string]$Quality = 'V0',
    [string]$BaseUrl = 'http://127.0.0.1:8188',
    [int]$TimeoutMinutes = 60,
    [string]$UnetName = 'minimax_music3_dit_fp16.safetensors',
    [string]$ClipName = 'minimax_music3_text_encoder_pruned_int8_convrot.safetensors',
    [string]$VaeName = 'minimax_music3_dav.safetensors'
)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

if ($Seed -le 0) { $Seed = Get-Random -Minimum 1 -Maximum 2147483646 }
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Force -Path $OutDir | Out-Null }

$promptFile = Join-Path $OutDir 'prompt.json'
& (Join-Path $here 'build_prompt.ps1') `
    -LyricsFile $LyricsFile `
    -CaptionFile $CaptionFile `
    -OutFile $promptFile `
    -Duration $Duration `
    -Seed $Seed `
    -Prefix $Prefix `
    -Steps $Steps `
    -CfgScale $CfgScale `
    -TopK $TopK `
    -Quality $Quality `
    -UnetName $UnetName `
    -ClipName $ClipName `
    -VaeName $VaeName

& (Join-Path $here 'run_prompt.ps1') -PromptFile $promptFile -BaseUrl $BaseUrl -OutDir $OutDir -TimeoutMinutes $TimeoutMinutes
exit $LASTEXITCODE
