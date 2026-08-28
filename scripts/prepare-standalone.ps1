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
$commit=(& git -C $project rev-parse HEAD).Trim()
if($LASTEXITCODE-ne0-or$commit-notmatch'^[0-9a-f]{40}$'){throw "A full Git commit is required for the release manifest"}
$manifest=[ordered]@{
  format="performance-tracker-release-package-v1"
  commit=$commit
  preparedAt=(Get-Date).ToUniversalTime().ToString("o")
  serverSha256=(Get-FileHash -LiteralPath (Join-Path $standalone "server.js") -Algorithm SHA256).Hash.ToLowerInvariant()
  packageSha256=(Get-FileHash -LiteralPath (Join-Path $standalone "package.json") -Algorithm SHA256).Hash.ToLowerInvariant()
}
$manifest|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $standalone "release-manifest.json") -Encoding utf8
Write-Host "Standalone package prepared at $standalone"
