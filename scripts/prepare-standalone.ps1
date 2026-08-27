param([string]$ProjectDirectory = (Split-Path $PSScriptRoot -Parent))
$ErrorActionPreference = "Stop"
$project = [System.IO.Path]::GetFullPath($ProjectDirectory)
$standalone = Join-Path $project ".next\standalone"
if (-not (Test-Path -LiteralPath (Join-Path $standalone "server.js"))) { throw "Run the production build before preparing the standalone package" }
$staticTarget = Join-Path $standalone ".next\static"
New-Item -ItemType Directory -Path $staticTarget -Force | Out-Null
Copy-Item -Path (Join-Path $project ".next\static\*") -Destination $staticTarget -Recurse -Force
$publicTarget = Join-Path $standalone "public"
New-Item -ItemType Directory -Path $publicTarget -Force | Out-Null
Copy-Item -Path (Join-Path $project "public\*") -Destination $publicTarget -Recurse -Force
Write-Host "Standalone package prepared at $standalone"
