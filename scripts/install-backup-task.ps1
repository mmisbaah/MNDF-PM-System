param([string]$ProjectDirectory=$PWD,[string]$DailyTime="02:00",[Parameter(Mandatory=$true)][string]$PublicKeyFile,[Parameter(Mandatory=$true)][string]$OffHostDirectory,[string]$PostgresBinDirectory="")
$ErrorActionPreference="Stop";$project=[System.IO.Path]::GetFullPath($ProjectDirectory);$script=Join-Path $project "scripts\backup-production.ps1";if(-not(Test-Path -LiteralPath $script)){throw "Backup script not found"}
$arguments="-NoProfile -File `"$script`" -PublicKeyFile `"$PublicKeyFile`" -OffHostDirectory `"$OffHostDirectory`"";if($PostgresBinDirectory){$arguments+=" -PostgresBinDirectory `"$PostgresBinDirectory`""}
$action=New-ScheduledTaskAction -Execute "powershell.exe" -Argument $arguments -WorkingDirectory $project
$trigger=New-ScheduledTaskTrigger -Daily -At $DailyTime;$settings=New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 2)
Register-ScheduledTask -TaskName "Performance-Tracker-Daily-Backup" -Action $action -Trigger $trigger -Settings $settings -Description "Daily encrypted and off-host verified backup for Performance Tracker" -Force
