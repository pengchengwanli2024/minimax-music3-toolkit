param(
    [Parameter(Mandatory = $true)][string]$LyricsFile,
    [Parameter(Mandatory = $true)][string]$CaptionFile,
    [string[]]$Seeds = @(),
    [int]$Count = 0,
    [double]$Duration = 120.0,
    [string[]]$Durations = @(),
    [string]$OutDir = './out',
    [string]$Prefix = 'Audio/song',
    [int]$Steps = 30,
    [double]$CfgScale = 1.7,
    [int]$TopK = 50,
    [ValidateSet('V0', '128k', '320k')][string]$Quality = 'V0',
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

# Durations: explicit list (e.g. -Durations 120,150) builds a seed x duration matrix.
$durationList = @()
foreach ($raw in $Durations) {
    foreach ($part in ($raw -split '[,;\s]+')) {
        $p = $part.Trim()
        if (-not $p) { continue }
        $d = 0.0
        if (-not [double]::TryParse($p, [ref]$d)) { throw "Invalid duration value: '$p' (expected seconds, e.g. 120)" }
        if ($d -gt 0) { $durationList += $d }
    }
}
if ($durationList.Count -eq 0) { $durationList = @($Duration) }
$multiDuration = $durationList.Count -gt 1

$files = @()
foreach ($seed in $seedList) {
    foreach ($dur in $durationList) {
        # sanitize only the file name, never the directory part
        $name = '{0}_seed{1}' -f (Split-Path -Leaf $Prefix), $seed
        if ($multiDuration) { $name += ('_{0}s' -f [int]$dur) }
        $leaf = ($name + '.json') -replace '[\\/:*?"<>|]', '_'
        $file = Join-Path $promptDir $leaf
        & (Join-Path $here 'build_prompt.ps1') `
            -LyricsFile $LyricsFile `
            -CaptionFile $CaptionFile `
            -OutFile $file `
            -Duration $dur `
            -Seed $seed `
            -Prefix $Prefix `
            -Steps $Steps `
            -CfgScale $CfgScale `
            -TopK $TopK `
            -Quality $Quality `
            -UnetName $UnetName `
            -ClipName $ClipName `
            -VaeName $VaeName
        $files += $file
    }
}

Write-Host ("built {0} take(s): seeds [{1}] x durations [{2}]" -f $files.Count, ($seedList -join ', '), (($durationList | ForEach-Object { [int]$_ }) -join ', '))
if ($DryRun) {
    $files | ForEach-Object { Write-Host ("  " + $_) }
    Write-Host 'DryRun: nothing submitted.'
    exit 0
}

& (Join-Path $here 'run_batch.ps1') -PromptFiles $files -BaseUrl $BaseUrl -OutDir $OutDir -TimeoutMinutes $TimeoutMinutes
exit $LASTEXITCODE
