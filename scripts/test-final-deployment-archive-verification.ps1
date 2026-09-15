$ErrorActionPreference='Stop'
$project=[IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent));$script=Get-Content -LiteralPath (Join-Path $project 'scripts\verify-final-deployment-archive.ps1') -Raw
function Assert-Match([string]$Pattern,[string]$Message){if($script-notmatch$Pattern){throw $Message}}
foreach($name in @('ApprovedVerifierSha256','ApprovedManifestSha256','ApprovedArchivePublicKeySha256','ApprovedNodeExecutableSha256','ApprovedExternalSigningHelperSha256','ApprovedClosureSha256','ApprovedInstallerApprovalSha256','ApprovedInstallerSha256','ApprovedInstallationReceiptSha256','ApprovedAuditManifestSha256','ApprovedCustodyHandoffSha256','ApprovedCustodyOutcomeSha256')){Assert-Match $name "Archive verifier must require $name"}
Assert-Match 'Initial verifier, Node\.js and signing helper trust inputs must remain outside the archive' 'Initial trust inputs must remain external'
Assert-Match 'exact fixed inventory' 'Archive verifier must reject added, missing and nested content'
Assert-Match 'Assert-OrdinaryPath' 'Archive verifier must reject redirected paths'
Assert-Match '\[IO\.FileShare\]::Read' 'Archive verifier must lock evidence against replacement'
Assert-Match 'O=OpenJS Foundation' 'Archive verifier must authenticate the external Node.js runtime'
Assert-Match '\$externalHelper verify.+final-archive-manifest' 'Archive verifier must authenticate the manifest from external code'
Assert-Match "format-ne'performance-tracker-final-deployment-archive-v1'" 'Archive verifier must enforce the versioned manifest'
Assert-Match 'Assert-ExactSchema.+runtime' 'Archive verifier must enforce exact runtime schema'
Assert-Match 'Final archive content fingerprint mismatch' 'Archive verifier must hash every payload file'
Assert-Match '& \$closureVerifier @verifyArgs' 'Archive verifier must run the authenticated enclosed closure verifier'
Write-Output 'PASS final deployment archive verification contract'
