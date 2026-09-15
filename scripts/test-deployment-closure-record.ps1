$ErrorActionPreference='Stop'
$project=[IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent));$script=Get-Content -LiteralPath (Join-Path $project 'scripts\new-deployment-closure-record.ps1') -Raw
function Assert-Match([string]$Pattern,[string]$Message){if($script-notmatch$Pattern){throw $Message}}
foreach($name in @('ApprovedInstallerApprovalSha256','ApprovedInstallerSha256','ApprovedInstallationReceiptSha256','ApprovedAuditManifestSha256','ApprovedCustodyHandoffSha256','ApprovedCustodyOutcomeSha256','ApprovedNodeExecutableSha256','ApprovedReleaseSigningHelperSha256')){Assert-Match $name "Closure must require $name"}
Assert-Match "ValidateSet\('RECEIVED','EXCEPTION'\)" 'Closure must accept only terminal custody outcomes'
Assert-Match 'Deployment closure and signature must not already exist' 'Closure evidence must be immutable'
Assert-Match 'Assert-OrdinaryPath' 'Closure must reject redirected evidence'
Assert-Match '\[IO\.FileShare\]::Read' 'Closure inputs must be locked against replacement'
Assert-Match 'O=OpenJS Foundation' 'Closure must authenticate Node.js'
Assert-Match 'foreach\(\$triple.+\$helper verify' 'Closure must authenticate every signed evidence layer'
foreach($label in @('Installer approval','Installation receipt','Audit manifest','Custody handoff','Custody outcome')){Assert-Match "Assert-ExactSchema.+$label" "Closure must enforce exact $label schema"}
Assert-Match 'Deployment closure evidence chain is not internally linked' 'Closure must link receipt, manifest, handoff and outcome'
Assert-Match "format='performance-tracker-deployment-closure-v1'" 'Closure must use a versioned schema'
Assert-Match 'custodyOutcomeType=\$OutcomeType' 'Closure must record the single terminal outcome type'
Assert-Match 'containsSecrets=\$false' 'Closure must be explicitly secret-free'
Assert-Match '\$helper sign \$closure \$privateKey \$closureSignature' 'Closure must be signed and independently preservable'
Write-Output 'PASS deployment closure record contract'

