$ErrorActionPreference='Stop'
$project=[IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent));$handoff=Get-Content -LiteralPath (Join-Path $project 'scripts\new-audit-bundle-custody-handoff.ps1') -Raw;$receipt=Get-Content -LiteralPath (Join-Path $project 'scripts\confirm-audit-bundle-custody-receipt.ps1') -Raw
function Assert-Match([string]$Source,[string]$Pattern,[string]$Message){if($Source-notmatch$Pattern){throw $Message}}
Assert-Match $handoff 'ValidateSet\(''OFFLINE_ENCRYPTED_MEDIA'',''SECURE_MANAGED_SHARE'',''PHYSICAL_CUSTODY''\)' 'Handoff must classify approved transfer methods'
Assert-Match $handoff 'Sender and receiver must be different Windows identities' 'Handoff must separate sender and receiver identities'
Assert-Match $handoff '& \$verifier -BundleDirectory' 'Handoff must independently verify the bundle first'
Assert-Match $handoff "format='performance-tracker-audit-custody-handoff-v1'" 'Handoff must use a versioned schema'
Assert-Match $handoff 'senderSid=\$senderSid;receiverSid=\$ReceiverSid' 'Handoff must bind both Windows identities'
Assert-Match $handoff '\$helper sign \$handoff \$privateKey \$signature' 'Handoff must be signed'
Assert-Match $receipt '\$helper verify \$handoff \$handoffSignature \$senderKey' 'Receiver must authenticate the sender handoff'
Assert-Match $receipt 'Only the named receiver Windows identity may confirm custody' 'Only the named receiver may acknowledge custody'
Assert-Match $receipt '& \$verifier -BundleDirectory' 'Receiver must verify the transferred bundle'
Assert-Match $receipt 'bundleVerified=\$true' 'Receipt must record successful bundle verification'
Assert-Match $receipt "format='performance-tracker-audit-custody-receipt-v1'" 'Receipt must use a versioned schema'
Assert-Match $receipt '\$helper sign \$receipt \$receiverPrivateKey \$receiptSignature' 'Receiver confirmation must be signed'
foreach($source in @($handoff,$receipt)){foreach($forbidden in @('DatabaseUrl','Password','application data')){if($source-match$forbidden){throw "Custody records reference forbidden material: $forbidden"}};Assert-Match $source 'containsSecrets=\$false' 'Custody records must be explicitly secret-free'}
Write-Output 'PASS audit bundle chain-of-custody contract'

