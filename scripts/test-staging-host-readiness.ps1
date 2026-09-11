$ErrorActionPreference='Stop'
$project=[IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
$verifier=Get-Content -LiteralPath (Join-Path $project 'scripts\verify-staging-host.ps1') -Raw
function Assert-Match([string]$Pattern,[string]$Message){if($verifier-notmatch$Pattern){throw $Message}}
Assert-Match 'ConfirmDisposableHost' 'Verifier must require explicit disposable-host acknowledgement'
Assert-Match 'ExpectedMachineName-ne\[Environment\]::MachineName' 'Verifier must bind operator intent to the exact host'
Assert-Match 'IsInRole\(\[Security\.Principal\.WindowsBuiltInRole\]::Administrator\)' 'Verifier must require elevation'
Assert-Match 'production installation path' 'Verifier must reject the production path'
Assert-Match 'RehearsalRoot must not already exist' 'Verifier must require a clean rehearsal root'
Assert-Match 'EvidenceDirectory must be outside RehearsalRoot' 'Evidence must survive rehearsal cleanup'
Assert-Match 'FileAttributes\]::ReparsePoint' 'Verifier must reject redirected staging paths'
Assert-Match "FileSystem-eq'NTFS'" 'Verifier must require NTFS for junction and ACL semantics'
Assert-Match 'SizeRemaining' 'Verifier must enforce staging capacity'
Assert-Match 'Get-NetTCPConnection' 'Verifier must detect a conflicting application listener'
Assert-Match 'Get-ScheduledTask' 'Verifier must reject pre-existing production tasks'
Assert-Match 'performance-tracker-staging-host-readiness-v1' 'Verifier must emit versioned evidence'
Assert-Match 'operatorSid' 'Evidence must bind the immutable operator SID'
Assert-Match 'FileMode\]::CreateNew' 'Evidence must never overwrite an existing record'
Write-Output 'PASS staging-host readiness contract'

