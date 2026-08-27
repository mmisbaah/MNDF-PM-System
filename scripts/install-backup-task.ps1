param([string]$ProjectDirectory=$PWD,[string]$DailyTime="02:00")
$ErrorActionPreference="Stop";$project=[System.IO.Path]::GetFullPath($ProjectDirectory);$script=Join-Path $project "scripts\backup-postgres.ps1";if(-not(Test-Path -LiteralPath $script)){throw "Backup script not found"}
$action=New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$script`"" -WorkingDirectory $project
$trigger=New-ScheduledTaskTrigger -Daily -At $DailyTime;$settings=New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 2)
Register-ScheduledTask -TaskName "Performance-Tracker-Daily-Backup" -Action $action -Trigger $trigger -Settings $settings -Description "Daily custom-format PostgreSQL backup for Performance Tracker" -Force
