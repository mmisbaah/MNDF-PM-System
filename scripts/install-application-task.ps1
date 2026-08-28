param(
  [string]$ProjectDirectory=(Split-Path $PSScriptRoot -Parent),
  [string]$EnvironmentFile="C:\PerformanceTracker\config\.env.production.local",
  [Parameter(Mandatory=$true)][Management.Automation.PSCredential]$ServiceCredential,
  [string]$TaskName="Performance-Tracker-Application"
)
$ErrorActionPreference="Stop"
$principal=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if(-not$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw "Application task installation must run from an elevated deployment PowerShell session"}
if($TaskName-ne"Performance-Tracker-Application"){throw "The production application task name is fixed"}
$project=[IO.Path]::GetFullPath($ProjectDirectory)
$environment=[IO.Path]::GetFullPath($EnvironmentFile)
$launcher=Join-Path $project "scripts\start-production.ps1"
$server=Join-Path $project ".next\standalone\server.js"
foreach($path in @($project,$environment,$launcher,$server)){if($path.Contains("'")){throw "Production paths may not contain apostrophes"}}
if(-not(Test-Path -LiteralPath $environment)){throw "Protected production environment file not found: $environment"}
if(-not(Test-Path -LiteralPath $launcher)){throw "Production launcher not found: $launcher"}
if(-not(Test-Path -LiteralPath $server)){throw "Prepared standalone server not found: $server"}
$arguments="-NoProfile -NonInteractive -ExecutionPolicy AllSigned -File `"$launcher`" -ProjectDirectory `"$project`" -EnvironmentFile `"$environment`""
$action=New-ScheduledTaskAction -Execute "powershell.exe" -Argument $arguments -WorkingDirectory $project
$trigger=New-ScheduledTaskTrigger -AtStartup
$settings=New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 5 -RestartInterval (New-TimeSpan -Minutes 1)
$username=$ServiceCredential.UserName
if([string]::IsNullOrWhiteSpace($username)){throw "A dedicated service-account username is required"}
$password=$ServiceCredential.GetNetworkCredential().Password
if([string]::IsNullOrWhiteSpace($password)){throw "The service-account password is required"}
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -User $username -Password $password -RunLevel Limited -Description "Runs the Performance Tracker application with bounded automatic restart" -Force|Out-Null
Start-ScheduledTask -TaskName $TaskName
Write-Output "Performance Tracker application task installed and started. The supplied credential was handed directly to Windows Task Scheduler and was not written to a file or command argument."
