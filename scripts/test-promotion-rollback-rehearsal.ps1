$ErrorActionPreference='Stop'
$project=[IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
$runner=Get-Content -LiteralPath (Join-Path $project 'scripts\run-promotion-rollback-rehearsal.ps1') -Raw
function Assert-Match([string]$Pattern,[string]$Message){if($runner-notmatch$Pattern){throw $Message}}
Assert-Match 'ConfirmDisposableHost' 'Rehearsal must require disposable-host acknowledgement'
Assert-Match 'IsInRole\(\[Security\.Principal\.WindowsBuiltInRole\]::Administrator\)' 'Rehearsal must require elevation'
Assert-Match 'must not use the production installation path' 'Rehearsal must reject production paths'
Assert-Match 'must be distinct directories' 'Rehearsal must require distinct lifecycle releases'
Assert-Match "HealthUrl must use loopback HTTP" 'Rehearsal health probe must remain local'
Assert-Match "EvidenceDirectory must be outside releases and CurrentLink" 'Evidence must survive release switching'
Assert-Match "OperationLog must be outside releases and CurrentLink" 'Journal must survive release switching'
Assert-Match "promote-release\.ps1" 'Rehearsal must reuse the guarded promotion implementation'
Assert-Match "-Initialize" 'Rehearsal must initialize a baseline release'
Assert-Match "Start-ScheduledTask" 'Rehearsal must start and health-check the baseline'
Assert-Match "Failure candidate unexpectedly promoted successfully" 'Rehearsal must require an induced unhealthy promotion'
Assert-Match "status-eq'ROLLED_BACK'" 'Rehearsal must verify automatic rollback in the journal'
Assert-Match 'performance-tracker-promotion-rollback-rehearsal-v1' 'Rehearsal must emit versioned evidence'
Assert-Match 'operatorSid' 'Evidence must bind the immutable operator SID'
Write-Output 'PASS promotion and rollback rehearsal contract'
