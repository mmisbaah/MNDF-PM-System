$ErrorActionPreference='Stop'
$project=[IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
$generator=Get-Content -LiteralPath (Join-Path $project 'scripts\new-unhealthy-rehearsal-release.ps1') -Raw
$planner=Get-Content -LiteralPath (Join-Path $project 'scripts\new-promotion-rehearsal-plan.ps1') -Raw
$runner=Get-Content -LiteralPath (Join-Path $project 'scripts\run-promotion-rollback-rehearsal.ps1') -Raw
function Assert-Match([string]$Value,[string]$Pattern,[string]$Message){if($Value-notmatch$Pattern){throw $Message}}
Assert-Match $generator 'RELEASE_SIGNING_KEY_PASSPHRASE' 'Generator must require encrypted rehearsal-key access'
Assert-Match $generator "response\.writeHead\(request\.url === '/api/health' \? 503 : 404" 'Failure server must return HTTP 503 for health'
Assert-Match $generator 'performance-tracker-unhealthy-rehearsal-v1' 'Failure package must have an explicit marker'
Assert-Match $generator 'release-integrity\.mjs.+create' 'Failure package must create a complete inventory'
Assert-Match $generator 'release-signing\.mjs.+sign' 'Failure package must be signed'
Assert-Match $generator 'release-signing\.mjs.+verify' 'Failure signature must be immediately verified'
Assert-Match $generator 'Remove-Item -LiteralPath \$output -Recurse -Force' 'Partial failure output must be cleaned'
Assert-Match $planner 'Failure release must contain a signed rehearsal-only marker' 'Plan must require the marker for failure role'
Assert-Match $planner 'release must not be marked rehearsal-only' 'Plan must reject marked healthy roles'
Assert-Match $runner 'Failure release is not marked as rehearsal-only' 'Runner must recheck the failure marker'
Assert-Match $runner 'release cannot be rehearsal-only' 'Runner must reject marked baseline or candidate roles'
Write-Output 'PASS unhealthy rehearsal release contract'

