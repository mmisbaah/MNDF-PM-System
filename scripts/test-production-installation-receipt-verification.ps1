$ErrorActionPreference='Stop'
$project=[IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent));$script=Get-Content -LiteralPath (Join-Path $project 'scripts\verify-production-installation-receipt.ps1') -Raw
function Assert-Match([string]$Pattern,[string]$Message){if($script-notmatch$Pattern){throw $Message}}
foreach($approval in @('ApprovedReceiptSha256','ApprovedReceiptPublicKeySha256','ApprovedNodeExecutableSha256','ApprovedReleaseSigningHelperSha256','ApprovedVerifierSha256')){Assert-Match $approval "Receipt verifier must require $approval"}
Assert-Match 'Get-Sha256 \$verifier.*?ApprovedVerifierSha256' 'Receipt verifier must validate its own independently approved fingerprint'
Assert-Match 'Assert-OrdinaryPath' 'Receipt verifier must reject redirected input paths'
Assert-Match 'FileAttributes\]::ReparsePoint' 'Receipt verifier must detect filesystem redirection'
Assert-Match '\[IO.FileShare\]::Read' 'Receipt verifier must lock every input against replacement'
Assert-Match '\$inputs=@\(\$verifier,\$receipt,\$signature,\$publicKey,\$node,\$helper\)' 'Receipt verifier must include itself in the locked input set'
Assert-Match 'O=OpenJS Foundation' 'Receipt verifier must authenticate the Node.js publisher'
Assert-Match '\$node \$helper verify \$receipt \$signature \$publicKey' 'Receipt verifier must cryptographically verify the detached signature'
Assert-Match "format-ne'performance-tracker-production-installation-receipt-v1'" 'Receipt verifier must enforce the versioned format'
Assert-Match "status-ne'PASS'" 'Receipt verifier must require a passed deployment'
Assert-Match 'containsSecrets-ne\$false' 'Receipt verifier must require a redacted receipt'
Assert-Match 'belongs to another deployment' 'Receipt verifier must bind the expected host, release ID and commit'
Assert-Match 'bound to another public key' 'Receipt verifier must bind the approved receipt key'
Assert-Match 'applicationTaskState-ne''Running''' 'Receipt verifier must require a running task result'
Assert-Match 'healthEndpoint-ne''loopback''' 'Receipt verifier must require loopback health evidence'
if($script-match'ReceiptSigningPrivateKey|RELEASE_SIGNING_KEY_PASSPHRASE|DatabaseUrl|Password'){throw 'Receipt verification must not require private keys, database URLs or passwords'}
Write-Output 'PASS production installation receipt verification contract'
