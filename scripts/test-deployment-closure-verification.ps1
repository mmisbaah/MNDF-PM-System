$ErrorActionPreference='Stop'
$project=[IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent));$script=Get-Content -LiteralPath (Join-Path $project 'scripts\verify-deployment-closure-record.ps1') -Raw
function Assert-Match([string]$Pattern,[string]$Message){if($script-notmatch$Pattern){throw $Message}}
foreach($name in @('ApprovedVerifierSha256','ApprovedClosureSha256','ApprovedClosurePublicKeySha256','ApprovedInstallerApprovalSha256','ApprovedInstallerSha256','ApprovedInstallationReceiptSha256','ApprovedAuditManifestSha256','ApprovedCustodyHandoffSha256','ApprovedCustodyOutcomeSha256','ApprovedNodeExecutableSha256','ApprovedReleaseSigningHelperSha256')){Assert-Match $name "Closure verifier must require $name"}
Assert-Match 'Assert-OrdinaryPath' 'Closure verifier must reject redirected evidence'
Assert-Match '\[IO\.FileShare\]::Read' 'Closure verifier must lock the entire evidence chain'
Assert-Match 'Get-Sha256 \$path' 'Closure verifier must check independent fingerprints'
Assert-Match 'O=OpenJS Foundation' 'Closure verifier must authenticate Node.js'
Assert-Match 'foreach\(\$triple.+\$helper verify' 'Closure verifier must authenticate all five signatures'
foreach($label in @('Deployment closure','Installer approval','Installation receipt','Audit manifest','Custody handoff','Custody outcome')){Assert-Match "Assert-ExactSchema.+$label" "Closure verifier must enforce exact $label schema"}
Assert-Match 'Closure timestamp' 'Closure verifier must validate its UTC timestamp'
Assert-Match 'Deployment closure does not bind the independently approved evidence' 'Closure verifier must pin every evidence hash'
Assert-Match 'Deployment closure evidence chain is not internally linked' 'Closure verifier must independently reconstruct the evidence chain'
foreach($forbidden in @('RELEASE_SIGNING_KEY_PASSPHRASE','SigningPrivateKey','DatabaseUrl','Password')){if($script-match$forbidden){throw "Offline closure verifier must not require sensitive input: $forbidden"}}
Write-Output 'PASS deployment closure verification contract'

