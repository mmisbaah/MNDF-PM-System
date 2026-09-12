$ErrorActionPreference='Stop'
$project=[IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
$builder=Get-Content -LiteralPath (Join-Path $project 'scripts\new-staging-rehearsal-bundle.ps1') -Raw
function Assert-Match([string]$Pattern,[string]$Message){if($builder-notmatch$Pattern){throw $Message}}
Assert-Match 'Bundle output directory must not already exist' 'Bundle creation must be non-overwriting'
Assert-Match 'FileAttributes\]::ReparsePoint' 'Bundle inputs must reject redirected filesystem entries'
Assert-Match 'forbidden secret-bearing filenames' 'Bundle must reject likely secret files'
Assert-Match 'release-signing\.mjs.+verify' 'Bundle must verify each release signature'
Assert-Match 'release-integrity\.mjs.+verify' 'Bundle must verify complete package inventories'
Assert-Match 'Failure release must be explicitly marked rehearsal-only' 'Failure package must have a test marker'
Assert-Match 'release cannot be marked rehearsal-only' 'Healthy roles must reject the test marker'
Assert-Match "rehearsalOnly=\`$true" 'Bundle manifest must identify test-only status'
Assert-Match 'FileMode\]::CreateNew' 'Bundle manifest must use exclusive creation'
Assert-Match 'contains no database credentials' 'Operator guide must state the secret boundary'
Assert-Match 'Never execute these commands against' 'Operator guide must warn against production use'
Assert-Match 'cleanup confirmation' 'Evidence checklist must include cleanup'
Write-Output 'PASS staging rehearsal bundle contract'

