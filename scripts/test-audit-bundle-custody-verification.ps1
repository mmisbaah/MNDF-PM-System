$ErrorActionPreference='Stop'
$project=[IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent));$script=Get-Content -LiteralPath (Join-Path $project 'scripts\verify-audit-bundle-chain-of-custody.ps1') -Raw
function Assert-Match([string]$Pattern,[string]$Message){if($script-notmatch$Pattern){throw $Message}}
foreach($name in @('ApprovedVerifierSha256','ApprovedHandoffSha256','ApprovedReceiptSha256','ApprovedSenderPublicKeySha256','ApprovedReceiverPublicKeySha256','ApprovedNodeExecutableSha256','ApprovedReleaseSigningHelperSha256','ExpectedManifestSha256','ExpectedBundlePublicKeySha256','ExpectedSenderSid','ExpectedReceiverSid','ExpectedTransferMethod')){Assert-Match $name "Custody verifier must require $name"}
Assert-Match 'Assert-OrdinaryPath' 'Custody verifier must reject redirected evidence'
Assert-Match '\[IO\.FileShare\]::Read' 'Custody verifier must lock every input against replacement'
Assert-Match 'Get-Sha256 \$path' 'Custody verifier must compare every independently approved fingerprint'
Assert-Match 'O=OpenJS Foundation' 'Custody verifier must authenticate the external runtime'
Assert-Match '\$helper verify \$handoff \$handoffSignature \$senderKey' 'Custody verifier must authenticate the sender handoff'
Assert-Match '\$helper verify \$receipt \$receiptSignature \$receiverKey' 'Custody verifier must authenticate the receiver receipt'
Assert-Match 'Assert-ExactSchema \$handoffRecord' 'Custody verifier must reject unknown handoff fields'
Assert-Match 'Assert-ExactSchema \$receiptRecord' 'Custody verifier must reject unknown receipt fields'
Assert-Match 'Custody receipt predates its handoff' 'Custody verifier must enforce chronology'
Assert-Match 'version 4 UUID' 'Custody verifier must validate transfer identifiers'
Assert-Match 'Custody receipt does not match its handoff' 'Custody verifier must link both records'
Assert-Match 'handoffSha256-ne\$ApprovedHandoffSha256' 'Custody receipt must bind the approved handoff'
foreach($forbidden in @('RELEASE_SIGNING_KEY_PASSPHRASE','SigningPrivateKey','DatabaseUrl','Password')){if($script-match$forbidden){throw "Independent custody verifier must not require sensitive input: $forbidden"}}
Write-Output 'PASS audit bundle custody verification contract'

