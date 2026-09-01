$ErrorActionPreference='Stop'
$project=[IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
$iss=Get-Content -LiteralPath (Join-Path $project 'installer\PerformanceTracker.iss') -Raw
$builder=Get-Content -LiteralPath (Join-Path $project 'installer\build-installer.ps1') -Raw
$completion=Get-Content -LiteralPath (Join-Path $project 'installer\assets\complete-installation.ps1') -Raw
$removal=Get-Content -LiteralPath (Join-Path $project 'installer\assets\remove-installation.ps1') -Raw
function Assert-Match([string]$Value,[string]$Pattern,[string]$Message){if($Value-notmatch$Pattern){throw $Message}}
Assert-Match $iss 'PrivilegesRequired=admin' 'Installer must require an approved elevated operator'
Assert-Match $iss 'uninsneveruninstall' 'Installer must retain immutable releases and protected configuration during uninstall'
Assert-Match $iss '\{#ReleaseSource\}\\\.next\\standalone\\\*' 'Installer must package the prepared standalone runtime'
Assert-Match $iss '\{#ReleaseSource\}\\scripts\\\*' 'Installer must package operational helpers'
if($iss-match'Source:\s*"\{#ReleaseSource\}\\\*"'){throw 'Installer must not package the repository root, source tree, caches, or development dependencies'}
Assert-Match $iss 'ExecutionPolicy AllSigned' 'Installer helpers must run under AllSigned policy'
Assert-Match $builder 'Get-AuthenticodeSignature' 'Builder must reject unsigned production helpers'
Assert-Match $builder 'signtool\.exe' 'Builder must Authenticode-sign the production executable'
Assert-Match $builder 'release-signing\.mjs.+verify' 'Builder must verify the release signature before compilation'
Assert-Match $completion 'release-integrity\.mjs.+verify' 'Installed files must be integrity-verified before provisioning'
Assert-Match $completion 'TrustedPublicKeySha256' 'Installed trust key must be pinned by fingerprint'
Assert-Match $removal 'deliberately retained' 'Uninstall must state its data-retention behavior'
Assert-Match $removal 'IndexOf\(\$root' 'Uninstall must verify each scheduled task belongs to this installation root'
Assert-Match $removal 'Retained \$taskName' 'Uninstall must preserve same-named tasks owned by another installation'
if($iss-match'(?i)(DATABASE_URL|AUTH_JWT_SECRET|MFA_ENCRYPTION_KEY)\s*='){throw 'Installer source must not embed application secrets'}
Write-Output 'Installer security contract tests passed.'
