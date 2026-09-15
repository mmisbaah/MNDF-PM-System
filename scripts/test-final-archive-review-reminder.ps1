$ErrorActionPreference='Stop'
$project=[IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent));$worker=Get-Content -LiteralPath (Join-Path $project 'scripts\check-final-archive-review-due.ps1') -Raw;$installer=Get-Content -LiteralPath (Join-Path $project 'scripts\install-final-archive-review-reminder-task.ps1') -Raw
function Assert-Match([string]$Text,[string]$Pattern,[string]$Message){if($Text-notmatch$Pattern){throw $Message}}
Assert-Match $worker 'ApprovedRetentionPolicySha256' 'Reminder must pin its policy'
Assert-Match $worker 'Assert-OrdinaryPath' 'Reminder must reject redirected inputs'
Assert-Match $worker '\[IO\.FileShare\]::Read' 'Reminder must lock trust inputs'
Assert-Match $worker 'O=OpenJS Foundation' 'Reminder must authenticate Node.js'
Assert-Match $worker '\$helper verify \$policy \$signature \$key' 'Reminder must authenticate the policy'
Assert-Match $worker 'exit 2' 'Overdue review must produce an observable task failure'
Assert-Match $installer 'New-ScheduledTaskTrigger -Daily' 'Reminder must run daily'
Assert-Match $installer 'ExecutionPolicy AllSigned' 'Reminder must require signed operational scripts'
Assert-Match $installer 'Performance-Tracker-Archive-Review-Reminder' 'Reminder task must use a fixed identity'
if($installer-match'PASSPHRASE|PrivateKey'){throw 'Scheduled reminder must not receive signing secrets'}
Write-Output 'PASS final archive review-reminder contract'
