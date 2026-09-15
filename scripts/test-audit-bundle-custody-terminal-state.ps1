$ErrorActionPreference='Stop'
$project=[IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent));$terminal=Get-Content -LiteralPath (Join-Path $project 'scripts\assert-audit-bundle-custody-terminal-state.ps1') -Raw;$verifier=Get-Content -LiteralPath (Join-Path $project 'scripts\verify-audit-bundle-custody-exception.ps1') -Raw
function Assert-Match([string]$Source,[string]$Pattern,[string]$Message){if($Source-notmatch$Pattern){throw $Message}}
Assert-Match $terminal 'Custody terminal outcome is incomplete' 'Terminal guard must reject half-written outcomes'
Assert-Match $terminal 'Custody transfer must have exactly one terminal outcome' 'Terminal guard must reject missing and conflicting outcomes'
Assert-Match $terminal 'Assert-OrdinaryPath' 'Terminal guard must reject redirected evidence'
Assert-Match $terminal '\[IO\.FileShare\]::Read' 'Terminal guard must lock the selected outcome'
Assert-Match $terminal 'Get-FileHash.+SHA256' 'Terminal guard must report fingerprints for independent approval'
foreach($name in @('ApprovedVerifierSha256','ApprovedHandoffSha256','ApprovedExceptionSha256','ApprovedSenderPublicKeySha256','ApprovedExceptionPublicKeySha256','ApprovedNodeExecutableSha256','ApprovedReleaseSigningHelperSha256','ApprovedCustodianSids')){Assert-Match $verifier $name "Exception verifier must require $name"}
Assert-Match $verifier 'O=OpenJS Foundation' 'Exception verifier must authenticate Node.js'
Assert-Match $verifier '\$helper verify \$handoff \$handoffSignature \$senderKey' 'Exception verifier must authenticate the handoff'
Assert-Match $verifier '\$helper verify \$exception \$exceptionSignature \$exceptionKey' 'Exception verifier must authenticate the exception'
Assert-Match $verifier 'Assert-ExactSchema \$exceptionRecord' 'Exception verifier must enforce the exact schema'
Assert-Match $verifier 'Custody exception chronology or deadline is invalid' 'Exception verifier must enforce chronology and overdue deadlines'
Assert-Match $verifier 'Custody exception signer is not independently approved' 'Exception verifier must authenticate the approved custodian SID'
foreach($forbidden in @('RELEASE_SIGNING_KEY_PASSPHRASE','SigningPrivateKey','DatabaseUrl','Password')){if($verifier-match$forbidden){throw "Independent exception verifier must not require sensitive input: $forbidden"}}
Write-Output 'PASS audit bundle custody terminal-state contract'

