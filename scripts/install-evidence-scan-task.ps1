param(
  [string]$ProjectDirectory = (Split-Path $PSScriptRoot -Parent),
  [string]$EnvironmentFile = "C:\PerformanceTracker\config\.env.production.local"
)
$ErrorActionPreference = "Stop"
$project = [System.IO.Path]::GetFullPath($ProjectDirectory)
$worker = Join-Path $project "scripts\scan-evidence-defender.ps1"
if (-not (Test-Path -LiteralPath $worker)) { throw "Evidence scanner worker not found" }
if (-not (Test-Path -LiteralPath $EnvironmentFile)) { throw "Protected production environment file not found" }
$command = "`$lines=Get-Content -LiteralPath '$EnvironmentFile';foreach(`$line in `$lines){if(`$line -match '^([A-Z0-9_]+)=(.*)$'){[Environment]::SetEnvironmentVariable(`$matches[1],`$matches[2],'Process')}};& '$worker'"
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -NonInteractive -ExecutionPolicy AllSigned -Command `"$command`""
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 1)
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
Register-ScheduledTask -TaskName "Performance-Tracker-Evidence-Scanner" -Action $action -Trigger $trigger -Settings $settings -Description "Scans pending Performance Tracker evidence with Microsoft Defender" -Force
