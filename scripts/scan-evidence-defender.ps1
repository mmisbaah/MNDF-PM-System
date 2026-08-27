param(
  [string]$BaseUrl = "http://127.0.0.1:3100",
  [int]$MaxAttempts = 3
)
$ErrorActionPreference = "Stop"
if ($BaseUrl -notmatch '^http://(127\.0\.0\.1|localhost)(:\d+)?$') { throw "The scanner must call the application over loopback" }
if ($MaxAttempts -lt 1 -or $MaxAttempts -gt 5) { throw "MaxAttempts must be between 1 and 5" }
$secret = $env:EVIDENCE_SCANNER_SECRET
$evidenceRoot = $env:EVIDENCE_STORAGE_ROOT
$quarantineRoot = $env:EVIDENCE_QUARANTINE_ROOT
if ([string]::IsNullOrWhiteSpace($secret) -or $secret.Length -lt 32) { throw "EVIDENCE_SCANNER_SECRET is required" }
if (-not [System.IO.Path]::IsPathRooted($evidenceRoot)) { throw "EVIDENCE_STORAGE_ROOT must be absolute" }
if (-not [System.IO.Path]::IsPathRooted($quarantineRoot)) { throw "EVIDENCE_QUARANTINE_ROOT must be absolute" }

$defender = Join-Path $env:ProgramFiles "Windows Defender\MpCmdRun.exe"
$platform = Join-Path $env:ProgramData "Microsoft\Windows Defender\Platform"
if (Test-Path -LiteralPath $platform) {
  $latest = Get-ChildItem -LiteralPath $platform -Directory | Sort-Object Name -Descending | Select-Object -First 1
  if ($latest -and (Test-Path -LiteralPath (Join-Path $latest.FullName "MpCmdRun.exe"))) { $defender = Join-Path $latest.FullName "MpCmdRun.exe" }
}
if (-not (Test-Path -LiteralPath $defender)) { throw "Microsoft Defender command-line scanner was not found" }

$headers = @{ Authorization = "Bearer $secret" }
$queue = Invoke-RestMethod -Method Get -Uri "$BaseUrl/api/internal/evidence-scan" -Headers $headers -TimeoutSec 20
$safeRoot = [System.IO.Path]::GetFullPath($evidenceRoot).TrimEnd('\') + '\'
$safeQuarantine = [System.IO.Path]::GetFullPath($quarantineRoot).TrimEnd('\') + '\'
New-Item -ItemType Directory -Path $safeQuarantine -Force | Out-Null

foreach ($item in @($queue.evidence)) {
  $relative = ($item.storage_key -replace '/', '\')
  $file = [System.IO.Path]::GetFullPath((Join-Path $safeRoot $relative))
  if (-not $file.StartsWith($safeRoot,[System.StringComparison]::OrdinalIgnoreCase)) { continue }
  $status = "FAILED"
  $quarantine = $false
  if (Test-Path -LiteralPath $file -PathType Leaf) {
    $digest = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($digest -ne ([string]$item.sha256_hex).ToLowerInvariant()) { $quarantine = $true }
    else {
      for ($attempt=1; $attempt -le $MaxAttempts; $attempt++) {
        & $defender -Scan -ScanType 3 -File $file -DisableRemediation | Out-Null
        $scanExit = $LASTEXITCODE
        if ($scanExit -eq 0) { $status = "CLEAN"; break }
        if ($scanExit -eq 2) { $status = "INFECTED"; $quarantine = $true; break }
        if ($attempt -lt $MaxAttempts) { Start-Sleep -Seconds ([Math]::Min(10,[Math]::Pow(2,$attempt))) }
      }
    }
  }
  if ($quarantine -and (Test-Path -LiteralPath $file)) {
    $destination = [System.IO.Path]::GetFullPath((Join-Path $safeQuarantine $relative))
    if ($destination.StartsWith($safeQuarantine,[System.StringComparison]::OrdinalIgnoreCase)) {
      New-Item -ItemType Directory -Path ([System.IO.Path]::GetDirectoryName($destination)) -Force | Out-Null
      Move-Item -LiteralPath $file -Destination $destination -Force
    }
  }
  $body = @{ tenantId=$item.tenant_id; uploadId=$item.upload_id; status=$status } | ConvertTo-Json -Compress
  Invoke-RestMethod -Method Post -Uri "$BaseUrl/api/internal/evidence-scan" -Headers $headers -ContentType "application/json" -Body $body -TimeoutSec 20 | Out-Null
}
Write-Host "Evidence scan queue processed: $(@($queue.evidence).Count) item(s)"
