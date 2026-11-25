param(
    [Parameter(Mandatory = $true)][string]$LyricsFile,
    [Parameter(Mandatory = $true)][string]$CaptionFile,
    [string[]]$Seeds = @(),
    [int]$Count = 0,
    [double]$Duration = 120.0,
    [string]$OutDir = './out',
    [string]$Prefix = 'Audio/song',
    [int]$Steps = 30,
    [double]$CfgScale = 1.7,
    [int]$TopK = 50,
    [string]$BaseUrl = 'http://127.0.0.1:8188',
    [int]$TimeoutMinutes = 120,
    [string]$UnetName = 'minimax_music3_dit_fp16.safetensors',
    [string]$ClipName = 'minimax_music3_text_encoder_pruned_int8_convrot.safetensors',
    [string]$VaeName = 'minimax_music3_dav.safetensors',
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

# Seeds: explicit list wins, otherwise generate -Count random seeds (default 2 takes).
# NOTE: with `pwsh -File`, `-Seeds 111,222` arrives as ONE string, so split on separators first.
$seedList = @()
foreach ($raw in $Seeds) {
    foreach ($part in ($raw -split '[,;\s]+')) {
        $p = $part.Trim()
        if (-not $p) { continue }
        $n = 0
        if (-not [int]::TryParse($p, [ref]$n)) { throw "Invalid seed value: '$p' (expected an integer)" }
        if ($n -gt 0) { $seedList += $n }
    }
}
if ($seedList.Count -eq 0) {
    if ($Count -le 0) { $Count = 2 }
    for ($i = 0; $i -lt $Count; $i++) { $seedList += Get-Random -Minimum 1 -Maximum 2147483646 }
}

$promptDir = Join-Path $OutDir 'prompts'
if (-not (Test-Path $promptDir)) { New-Item -ItemType Directory -Force -Path $promptDir | Out-Null }

$files = @()
foreach ($seed in $seedList) {
    # sanitize only the file name, never the directory part
    $leaf = ('{0}_seed{1}.json' -f (Split-Path -Leaf $Prefix), $seed) -replace '[\\/:*?"<>|]', '_'
    $file = Join-Path $promptDir $leaf
    & (Join-Path $here 'build_prompt.ps1') `
        -LyricsFile $LyricsFile `
        -CaptionFile $CaptionFile `
        -OutFile $file `
        -Duration $Duration `
        -Seed $seed `
        -Prefix $Prefix `
        -Steps $Steps `
        -CfgScale $CfgScale `
        -TopK $TopK `
        -UnetName $UnetName `
        -ClipName $ClipName `
        -VaeName $VaeName
    $files += $file
}

Write-Host ("built {0} take(s): {1}" -f $files.Count, ($seedList -join ', '))
if ($DryRun) {
    $files | ForEach-Object { Write-Host ("  " + $_) }
    Write-Host 'DryRun: nothing submitted.'
    exit 0
}

& (Join-Path $here 'run_batch.ps1') -PromptFiles $files -BaseUrl $BaseUrl -OutDir $OutDir -TimeoutMinutes $TimeoutMinutes
exit $LASTEXITCODE
