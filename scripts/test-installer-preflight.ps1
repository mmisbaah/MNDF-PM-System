$ErrorActionPreference='Stop'
$project=[IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
$launcher=Get-Content -LiteralPath (Join-Path $project 'scripts\install-verified-package.ps1') -Raw
function Assert-Match([string]$Pattern,[string]$Message){if($launcher-notmatch$Pattern){throw $Message}}
Assert-Match '\[switch\]\$PreflightOnly' 'Installer launcher must expose a preflight-only mode'
Assert-Match 'ApprovedPreflightReportSha256 is required for elevated installation' 'Installation must require independent preflight approval'
Assert-Match 'ApprovedPreflightReportSha256 must not be supplied while creating' 'Preflight creation must not accept a preselected output hash'
Assert-Match 'PreflightOnly must run from a non-elevated operator session' 'Preflight must refuse an already elevated session'
Assert-Match "format='performance-tracker-install-preflight-v1'" 'Preflight must use a versioned report schema'
Assert-Match "status='PASS'" 'Only a fully passed verification may create a preflight report'
Assert-Match "verificationMode='NON_ELEVATED_PREFLIGHT'" 'Report must identify its non-elevated verification scope'
Assert-Match 'containsSecrets=\$false' 'Report must explicitly remain secret-free'
Assert-Match 'installerLaunched=\$false' 'Report must state that no installer was launched'
Assert-Match '\[IO.FileMode\]::CreateNew' 'Preflight evidence must never overwrite an existing report'
Assert-Match 'Flush\(\$true\)' 'Preflight report must be durably flushed before success'
Assert-Match 'Get-FileHash -LiteralPath \$reportPath' 'Preflight must produce an independently recordable fingerprint'
Assert-Match 'Assert-ProtectedPackageAcl .*?\$preflightReport' 'Installation must enforce protected ACLs on the preflight report'
Assert-Match '\$lockedBundle\+=\$preflightReport' 'Installation must lock the preflight report against replacement'
Assert-Match 'Installation preflight report fingerprint does not match independent approval' 'Installation must verify the independently approved preflight hash'
Assert-Match 'Assert-InstallPreflightReport \$preflight' 'Installation must semantically validate preflight evidence'
Assert-Match 'packageCustodiansSha256=\$custodianFingerprint' 'Preflight must bind the redacted custodian-set fingerprint'
$verifyIndex=$launcher.IndexOf('& $verifier @verification')
$reportIndex=$launcher.IndexOf("format='performance-tracker-install-preflight-v1'")
$launchIndex=$launcher.IndexOf('Start-Process -FilePath $installer')
if($verifyIndex-lt0-or$reportIndex-lt$verifyIndex){throw 'Preflight report must be created only after full package verification'}
if($launchIndex-lt$reportIndex){throw 'Preflight branch must be evaluated before any installer launch'}
if($launcher-notmatch'(?s)if\(\$PreflightOnly\)\{\s*\$report=.*?\}\s*else\{\s*\$preflightHash=.*?\$process=Start-Process'){throw 'Preflight must bypass installer execution'}
Write-Output 'PASS installer preflight contract'
