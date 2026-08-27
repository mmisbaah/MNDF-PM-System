param(
  [string]$ProjectDirectory = (Split-Path $PSScriptRoot -Parent),
  [string]$EnvironmentFile = ".env.production.local"
)
$ErrorActionPreference = "Stop"
$project = [System.IO.Path]::GetFullPath($ProjectDirectory)
$envPath = if ([System.IO.Path]::IsPathRooted($EnvironmentFile)) { $EnvironmentFile } else { Join-Path $project $EnvironmentFile }
if (-not (Test-Path -LiteralPath $envPath)) { throw "Protected production environment file not found: $envPath" }
$standalone = Join-Path $project ".next\standalone"
$server = Join-Path $standalone "server.js"
if (-not (Test-Path -LiteralPath $server)) { throw "Prepared standalone server not found. Run build and prepare-standalone.ps1 first." }
& node "--env-file=$envPath" (Join-Path $project "scripts\validate-production-env.mjs")
if ($LASTEXITCODE -ne 0) { throw "Production environment validation failed" }
Push-Location $standalone
try {
  & node "--env-file=$envPath" $server
  if ($LASTEXITCODE -ne 0) { throw "Performance Tracker exited with code $LASTEXITCODE" }
} finally { Pop-Location }
