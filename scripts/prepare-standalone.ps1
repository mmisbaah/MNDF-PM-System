param([string]$ProjectDirectory = (Split-Path $PSScriptRoot -Parent))
$ErrorActionPreference = "Stop"
$project = [System.IO.Path]::GetFullPath($ProjectDirectory)
. (Join-Path $PSScriptRoot 'release-source-check.ps1')
$commit=Get-CleanReleaseCommit $project
$standalone = Join-Path $project ".next\standalone"
if (-not (Test-Path -LiteralPath (Join-Path $standalone "server.js"))) { throw "Run the production build before preparing the standalone package" }
& node (Join-Path $PSScriptRoot 'release-build-provenance.mjs') verify $project $commit
if($LASTEXITCODE -ne 0){throw 'Build provenance rejected. Run release-build.ps1 from a fresh clean checkout.'}
if((Get-CleanReleaseCommit $project) -ne $commit){throw 'Release source changed during packaging'}
# Do not regenerate the manifest: it is bound to the completed release build.
Write-Host "Standalone package prepared at $standalone"
