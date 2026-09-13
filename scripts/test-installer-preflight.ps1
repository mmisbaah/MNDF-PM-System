$ErrorActionPreference='Stop'
$project=[IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
$launcher=Get-Content -LiteralPath (Join-Path $project 'scripts\install-verified-package.ps1') -Raw
function Assert-Match([string]$Pattern,[string]$Message){if($launcher-notmatch$Pattern){throw $Message}}
Assert-Match '\[switch\]\$PreflightOnly' 'Installer launcher must expose a preflight-only mode'
Assert-Match 'PreflightReportPath is required with PreflightOnly' 'Preflight must require an evidence destination'
Assert-Match 'PreflightReportPath may only be used with PreflightOnly' 'Installation must reject ambiguous report arguments'
Assert-Match 'PreflightOnly must run from a non-elevated operator session' 'Preflight must refuse an already elevated session'
Assert-Match "format='performance-tracker-install-preflight-v1'" 'Preflight must use a versioned report schema'
Assert-Match "status='PASS'" 'Only a fully passed verification may create a preflight report'
Assert-Match "verificationMode='NON_ELEVATED_PREFLIGHT'" 'Report must identify its non-elevated verification scope'
Assert-Match 'containsSecrets=\$false' 'Report must explicitly remain secret-free'
Assert-Match 'installerLaunched=\$false' 'Report must state that no installer was launched'
Assert-Match '\[IO.FileMode\]::CreateNew' 'Preflight evidence must never overwrite an existing report'
Assert-Match 'Flush\(\$true\)' 'Preflight report must be durably flushed before success'
Assert-Match 'Get-FileHash -LiteralPath \$reportPath' 'Preflight must produce an independently recordable fingerprint'
$verifyIndex=$launcher.IndexOf('& $verifier @verification')
$reportIndex=$launcher.IndexOf("format='performance-tracker-install-preflight-v1'")
$launchIndex=$launcher.IndexOf('Start-Process -FilePath $installer')
if($verifyIndex-lt0-or$reportIndex-lt$verifyIndex){throw 'Preflight report must be created only after full package verification'}
if($launchIndex-lt$reportIndex){throw 'Preflight branch must be evaluated before any installer launch'}
if($launcher-notmatch'(?s)if\(\$PreflightOnly\).*?else\{\s*\$process=Start-Process'){throw 'Preflight must bypass installer execution'}
Write-Output 'PASS installer preflight contract'
