$ErrorActionPreference='Stop'
$project=[IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent));$script=Get-Content -LiteralPath (Join-Path $project 'scripts\new-final-deployment-archive.ps1') -Raw
function Assert-Match([string]$Pattern,[string]$Message){if($script-notmatch$Pattern){throw $Message}}
Assert-Match 'Final deployment archive destination must not already exist' 'Final archive must never overwrite retained evidence'
Assert-Match 'Final archive private key must remain outside the archive' 'Final archive must exclude its private key'
Assert-Match 'exact fixed inventory' 'Archive staging must reject missing, added and nested evidence'
foreach($name in @('installer-approval.json','installation-receipt.json','audit-manifest.json','custody-handoff.json','custody-outcome.json','deployment-closure.json','verify-deployment-closure-record.ps1','release-signing.mjs','archive-public.pem')){Assert-Match ([regex]::Escape($name)) "Final archive must contain $name"}
Assert-Match '& \$verifier @verifyArgs' 'Final archive must verify the complete closure chain before copying'
Assert-Match 'O=OpenJS Foundation' 'Final archive must authenticate external Node.js'
Assert-Match "format='performance-tracker-final-deployment-archive-v1'" 'Final archive must use a versioned manifest'
Assert-Match 'bundled=\$false' 'Final archive must record that Node.js remains external'
Assert-Match 'containsSecrets=\$false' 'Final archive must be explicitly secret-free'
Assert-Match '\$helper sign \$manifest \$privateKey \$signature' 'Final archive manifest must be signed'
Assert-Match '\$helper verify \$manifest \$signature' 'Final archive signature must be immediately verified'
Write-Output 'PASS final deployment archive contract'

