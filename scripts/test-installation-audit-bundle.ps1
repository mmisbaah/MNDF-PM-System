$ErrorActionPreference='Stop'
$project=[IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent));$script=Get-Content -LiteralPath (Join-Path $project 'scripts\new-installation-audit-bundle.ps1') -Raw
function Assert-Match([string]$Pattern,[string]$Message){if($script-notmatch$Pattern){throw $Message}}
Assert-Match 'Audit bundle destination must not already exist' 'Audit bundle must not overwrite prior evidence'
Assert-Match 'Audit bundle private key must remain outside the bundle' 'Audit private key must not enter the bundle'
Assert-Match 'Assert-OrdinaryPath' 'Audit bundle must reject redirected sources'
Assert-Match '& \$verifier -ReceiptPath' 'Audit bundle must verify receipt evidence before copying'
Assert-Match 'ApprovedReceiptVerifierSha256' 'Audit bundle must pin the receipt verifier'
Assert-Match 'O=OpenJS Foundation' 'Audit bundle must authenticate the external runtime'
Assert-Match "nodeVersion-notmatch'\^v24" 'Audit bundle must require Node.js 24'
Assert-Match 'installation-receipt\.json''=\$receipt' 'Audit bundle must use fixed portable filenames'
Assert-Match 'bundle-public\.pem''=\$bundleKey' 'Audit bundle must include its public trust key'
Assert-Match "format='performance-tracker-installation-audit-bundle-v1'" 'Audit bundle must use a versioned manifest'
Assert-Match 'bundled=\$false' 'Audit bundle must record that the approved runtime is external'
Assert-Match 'containsSecrets=\$false' 'Audit bundle must be explicitly secret-free'
Assert-Match '\$helper sign \$manifestPath \$privateKey \$manifestSignature' 'Audit bundle manifest must be signed'
Assert-Match '\$helper verify \$manifestPath \$manifestSignature' 'Audit bundle signature must be immediately verified'
foreach($forbidden in @('DatabaseUrl','Password','\.env','application-.*\.log')){if($script-match$forbidden){throw "Audit bundle source references forbidden secret-bearing material: $forbidden"}}
Write-Output 'PASS installation audit bundle contract'
