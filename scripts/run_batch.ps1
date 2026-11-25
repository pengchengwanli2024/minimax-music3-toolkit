param(
    [Parameter(Mandatory = $true)][string[]]$PromptFiles,
    [string]$BaseUrl = 'http://127.0.0.1:8188',
    [string]$OutDir = '',
    [int]$TimeoutMinutes = 120,
    [int]$PollSeconds = 15
)
$ErrorActionPreference = 'Stop'

$jobs = @()
foreach ($f in $PromptFiles) {
    if (-not (Test-Path $f)) { Write-Host "SKIP missing: $f"; continue }
    $prompt = Get-Content $f -Raw | ConvertFrom-Json
    $body = @{ prompt = $prompt; client_id = 'mm3b-' + [guid]::NewGuid().ToString('N').Substring(0, 10) } | ConvertTo-Json -Depth 30
    try {
        $r = Invoke-RestMethod -Uri "$BaseUrl/prompt" -Method Post -Body $body -ContentType 'application/json' -TimeoutSec 60
        Write-Host ("SUBMITTED {0} -> {1}" -f (Split-Path $f -Leaf), $r.prompt_id)
        $jobs += [pscustomobject]@{ File = $f; Id = $r.prompt_id; Done = $false; Result = $null }
    } catch {
        Write-Host ("SUBMIT_FAILED {0}: {1}" -f $f, $_.Exception.Message)
        if ($_.ErrorDetails.Message) { Write-Host $_.ErrorDetails.Message }
    }
}
if ($jobs.Count -eq 0) { Write-Host 'Nothing submitted.'; exit 1 }

function Save-NodeOutputs($entry, $outDir) {
    if (-not $outDir) { return 0 }
    if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }
    $saved = 0
    foreach ($nodeProp in $entry.outputs.PSObject.Properties) {
        $nodeOut = $nodeProp.Value
        foreach ($kind in @('audio', 'images', 'gifs')) {
            if (-not $nodeOut.$kind) { continue }
            foreach ($item in @($nodeOut.$kind)) {
                if (-not $item.filename) { continue }
                $target = Join-Path $outDir $item.filename
                $q = 'filename=' + [uri]::EscapeDataString($item.filename) +
                     '&subfolder=' + [uri]::EscapeDataString([string]$item.subfolder) +
                     '&type=' + [uri]::EscapeDataString([string]$item.type)
                try {
                    Invoke-WebRequest -Uri "$BaseUrl/view?$q" -OutFile $target -TimeoutSec 120 | Out-Null
                    Write-Host ("  saved: " + $target)
                    $saved++
                } catch { Write-Host ("  download failed: " + $item.filename) }
            }
        }
    }
    return $saved
}

$start = Get-Date
$deadline = $start.AddMinutes($TimeoutMinutes)
while ((Get-Date) -lt $deadline) {
    $pendingJobs = @($jobs | Where-Object { -not $_.Done })
    if ($pendingJobs.Count -eq 0) { break }
    Start-Sleep -Seconds $PollSeconds
    foreach ($j in $pendingJobs) {
        try { $h = Invoke-RestMethod -Uri "$BaseUrl/history/$($j.Id)" -TimeoutSec 30 } catch { continue }
        if ($h.PSObject.Properties.Name -notcontains $j.Id) { continue }
        $entry = $h.($j.Id)
        $j.Done = $true
        $j.Result = $entry
        Write-Host ("DONE {0} status={1} elapsed={2}s" -f (Split-Path $j.File -Leaf), $entry.status.status_str, [int]((Get-Date) - $start).TotalSeconds)
        if ($entry.status.status_str -ne 'error') { Save-NodeOutputs $entry $OutDir | Out-Null }
        else { Write-Host '  (run failed, see ComfyUI log)' }
    }
    try {
        $q = Invoke-RestMethod -Uri "$BaseUrl/queue" -TimeoutSec 20
        Write-Host ("[{0}s] running={1} pending={2} done={3}/{4}" -f [int]((Get-Date) - $start).TotalSeconds, @($q.queue_running).Count, @($q.queue_pending).Count, @($jobs | Where-Object { $_.Done }).Count, $jobs.Count)
    } catch { }
}

$left = @($jobs | Where-Object { -not $_.Done })
if ($left.Count -gt 0) { Write-Host ("TIMEOUT: {0} still running" -f $left.Count); exit 2 }
Write-Host 'ALL DONE'
exit 0
