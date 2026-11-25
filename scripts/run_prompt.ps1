param(
    [Parameter(Mandatory = $true)][string]$PromptFile,
    [string]$BaseUrl = 'http://127.0.0.1:8188',
    [string]$OutDir = '',
    [int]$TimeoutMinutes = 60,
    [int]$PollSeconds = 10
)
$ErrorActionPreference = 'Stop'

if (-not (Test-Path $PromptFile)) { throw "PromptFile not found: $PromptFile" }

$prompt = Get-Content $PromptFile -Raw | ConvertFrom-Json
$body = @{ prompt = $prompt; client_id = 'mm3-' + [guid]::NewGuid().ToString('N').Substring(0, 12) } | ConvertTo-Json -Depth 30
try {
    $resp = Invoke-RestMethod -Uri "$BaseUrl/prompt" -Method Post -Body $body -ContentType 'application/json' -TimeoutSec 60
} catch {
    Write-Host "SUBMIT_FAILED: $($_.Exception.Message)"
    if ($_.ErrorDetails.Message) { Write-Host "BODY: $($_.ErrorDetails.Message)" }
    exit 1
}
$id = $resp.prompt_id
Write-Host ("SUBMITTED prompt_id={0}" -f $id)

$start = Get-Date
$deadline = $start.AddMinutes($TimeoutMinutes)
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds $PollSeconds
    try { $h = Invoke-RestMethod -Uri "$BaseUrl/history/$id" -TimeoutSec 30 } catch { continue }
    if ($h.PSObject.Properties.Name -notcontains $id) {
        try {
            $q = Invoke-RestMethod -Uri "$BaseUrl/queue" -TimeoutSec 20
            Write-Host ("[{0}s] running={1} pending={2}" -f [int]((Get-Date) - $start).TotalSeconds, @($q.queue_running).Count, @($q.queue_pending).Count)
        } catch { }
        continue
    }

    $entry = $h.$id
    Write-Host ("=== DONE status={0} elapsed={1}s ===" -f $entry.status.status_str, [int]((Get-Date) - $start).TotalSeconds)
    if ($entry.status.status_str -eq 'error') {
        $entry.status.messages | Where-Object { $_[0] -eq 'execution_error' } | ForEach-Object { Write-Host ("ERROR: " + ($_ | ConvertTo-Json -Depth 6 -Compress)) }
        exit 1
    }

    $saved = 0
    foreach ($nodeProp in $entry.outputs.PSObject.Properties) {
        $nodeOut = $nodeProp.Value
        foreach ($kind in @('audio', 'images', 'gifs')) {
            if (-not $nodeOut.$kind) { continue }
            foreach ($item in @($nodeOut.$kind)) {
                if (-not $item.filename) { continue }
                if ($OutDir) {
                    if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Force -Path $OutDir | Out-Null }
                    $target = Join-Path $OutDir $item.filename
                    $q = 'filename=' + [uri]::EscapeDataString($item.filename) +
                         '&subfolder=' + [uri]::EscapeDataString([string]$item.subfolder) +
                         '&type=' + [uri]::EscapeDataString([string]$item.type)
                    try {
                        Invoke-WebRequest -Uri "$BaseUrl/view?$q" -OutFile $target -TimeoutSec 120 | Out-Null
                        Write-Host ("saved: " + $target)
                        $saved++
                    } catch { Write-Host ("download failed: {0} ({1})" -f $item.filename, $_.Exception.Message) }
                } else {
                    Write-Host ("output: {0}/{1}" -f $item.subfolder, $item.filename)
                }
            }
        }
    }
    if ($OutDir -and $saved -eq 0) { Write-Host 'WARNING: run succeeded but no output file was downloaded (check the workflow output node).' }
    exit 0
}
Write-Host 'TIMEOUT'
exit 2
