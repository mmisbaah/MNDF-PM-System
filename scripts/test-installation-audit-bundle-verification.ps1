$ErrorActionPreference='Stop'
$project=[IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent));$script=Get-Content -LiteralPath (Join-Path $project 'scripts\verify-installation-audit-bundle.ps1') -Raw
function Assert-Match([string]$Pattern,[string]$Message){if($script-notmatch$Pattern){throw $Message}}
foreach($approval in @('ApprovedVerifierSha256','ApprovedManifestSha256','ApprovedBundlePublicKeySha256','ApprovedNodeExecutableSha256','ApprovedExternalSigningHelperSha256')){Assert-Match $approval "Audit verifier must require $approval"}
Assert-Match 'Initial audit trust inputs must remain outside the bundle' 'Initial trust inputs must be independently delivered'
Assert-Match 'Audit bundle has added, missing, or unexpected files' 'Audit verifier must enforce a fixed top-level inventory'
Assert-Match 'Assert-OrdinaryPath' 'Audit verifier must reject filesystem redirection'
Assert-Match '\[IO.FileShare\]::Read' 'Audit verifier must lock every input against replacement'
Assert-Match 'Get-Sha256 \$verifier.*?ApprovedVerifierSha256' 'Audit verifier must authenticate itself'
Assert-Match 'O=OpenJS Foundation' 'Audit verifier must authenticate Node.js'
Assert-Match '\$externalHelper verify \$manifest \$manifestSignature \$bundleKey' 'Audit verifier must authenticate the bundle before trusting its inventory'
Assert-Match 'Audit bundle inventory is incomplete or contains unknown files' 'Audit verifier must reject inventory schema changes'
Assert-Match 'Audit bundle file failed inventory verification' 'Audit verifier must hash every bundled payload'
Assert-Match '& \$receiptVerifier -ReceiptPath' 'Audit verifier must independently verify the enclosed receipt'
if($script-match'RELEASE_SIGNING_KEY_PASSPHRASE|SigningPrivateKey|DatabaseUrl|Password'){throw 'Audit bundle verification must not require secrets'}
Write-Output 'PASS installation audit bundle verification contract'
