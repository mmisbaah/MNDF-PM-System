$ErrorActionPreference='Stop'
$project=[IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
$generator=Get-Content -LiteralPath (Join-Path $project 'scripts\new-promotion-rehearsal-plan.ps1') -Raw
$runner=Get-Content -LiteralPath (Join-Path $project 'scripts\run-promotion-rollback-rehearsal.ps1') -Raw
function Assert-Match([string]$Value,[string]$Pattern,[string]$Message){if($Value-notmatch$Pattern){throw $Message}}
Assert-Match $generator '\[ValidateRange\(1,14\)\]' 'Plan validity must be capped at 14 days'
Assert-Match $generator 'release-signing\.mjs' 'Generator must verify release signatures'
Assert-Match $generator 'release-integrity\.mjs' 'Generator must verify full package integrity'
Assert-Match $generator 'three distinct source commits' 'Generator must bind three distinct builds'
Assert-Match $generator 'FileMode\]::CreateNew' 'Generator must never overwrite a plan'
Assert-Match $generator 'authorizerSid' 'Plan must bind the authorizer SID'
Assert-Match $runner 'ApprovedRehearsalPlanSha256' 'Runner must require independent plan fingerprint approval'
Assert-Match $runner 'schema is incomplete or contains unknown fields' 'Runner must require an exact plan schema'
Assert-Match $runner 'belongs to a different host' 'Runner must bind the plan to the staging host'
Assert-Match $runner 'invalid or expired' 'Runner must enforce approval validity'
Assert-Match $runner 'release evidence changed after plan approval' 'Runner must detect staged release changes'
Write-Output 'PASS promotion rehearsal plan contract'

