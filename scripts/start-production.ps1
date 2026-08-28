param(
  [string]$ProjectDirectory = (Split-Path $PSScriptRoot -Parent),
  [string]$EnvironmentFile = ".env.production.local",
  [string]$LogDirectory = "C:\PerformanceTracker\logs\application"
)
$ErrorActionPreference = "Stop"
$project = [System.IO.Path]::GetFullPath($ProjectDirectory)
$envPath = if ([System.IO.Path]::IsPathRooted($EnvironmentFile)) { $EnvironmentFile } else { Join-Path $project $EnvironmentFile }
if (-not (Test-Path -LiteralPath $envPath)) { throw "Protected production environment file not found: $envPath" }
$standalone = Join-Path $project ".next\standalone"
$server = Join-Path $standalone "server.js"
if (-not (Test-Path -LiteralPath $server)) { throw "Prepared standalone server not found. Run build and prepare-standalone.ps1 first." }
. (Join-Path $PSScriptRoot "application-log-redaction.ps1")
$logs=[IO.Path]::GetFullPath($LogDirectory)
$projectNormalized=$project.TrimEnd('\')
if($logs-eq$projectNormalized-or$logs.StartsWith("$projectNormalized\",[StringComparison]::OrdinalIgnoreCase)){throw "Application logs must be outside the release directory"}
New-Item -ItemType Directory -Path $logs -Force|Out-Null
$started=(Get-Date).ToUniversalTime();$logPath=Join-Path $logs "application-$($started.ToString('yyyyMMddTHHmmssZ'))-$PID.log"
& node "--env-file=$envPath" (Join-Path $project "scripts\validate-production-env.mjs")
if ($LASTEXITCODE -ne 0) { throw "Production environment validation failed" }
Push-Location $standalone
try {
  "$((Get-Date).ToUniversalTime().ToString('o')) INFO Performance Tracker process starting"|Set-Content -LiteralPath $logPath -Encoding utf8
  & node "--env-file=$envPath" $server 2>&1|ForEach-Object{
    $line=Protect-ApplicationLogLine ([string]$_)
    "$((Get-Date).ToUniversalTime().ToString('o')) APP $line"|Add-Content -LiteralPath $logPath -Encoding utf8
  }
  $exitCode=$LASTEXITCODE
  "$((Get-Date).ToUniversalTime().ToString('o')) INFO Performance Tracker process exited code=$exitCode"|Add-Content -LiteralPath $logPath -Encoding utf8
  if ($exitCode -ne 0) { throw "Performance Tracker exited with code $exitCode; sanitized diagnostics are in $logPath" }
} finally { Pop-Location }
