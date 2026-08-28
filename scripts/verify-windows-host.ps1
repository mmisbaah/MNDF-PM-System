param(
  [int]$ApplicationPort=3100,
  [int]$DatabasePort=5432,
  [string[]]$RequiredTaskNames=@("Performance-Tracker-Application","Performance-Tracker-Scheduled-Jobs","Performance-Tracker-Evidence-Scanner","Performance-Tracker-Daily-Backup","Performance-Tracker-Audit-Export","Performance-Tracker-Operations-Monitor")
)
$ErrorActionPreference="Stop"
$principal=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if(-not$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw "Windows host readiness verification must run from an elevated operations PowerShell session"}
$failures=[Collections.Generic.List[string]]::new()
foreach($port in @($ApplicationPort,$DatabasePort)|Where-Object{$_-gt0}){
  if($port-lt1-or$port-gt65535){throw "Ports must be between 1 and 65535"}
  $listeners=@(Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue)
  if(-not$listeners){$failures.Add("No listener was found on required internal port $port");continue}
  foreach($listener in $listeners){if($listener.LocalAddress-notin@("127.0.0.1","::1")){$failures.Add("Port $port is exposed on $($listener.LocalAddress); it must listen only on loopback")}}
}
foreach($profile in @(Get-NetFirewallProfile -ErrorAction Stop)){if(-not$profile.Enabled){$failures.Add("Windows Firewall profile is disabled: $($profile.Name)")}}
$timeService=Get-Service -Name W32Time -ErrorAction SilentlyContinue
if(-not$timeService-or$timeService.Status-ne"Running"){$failures.Add("Windows Time service is not running")}else{
  $timeStatus=(& w32tm /query /status 2>&1)-join"`n"
  if($LASTEXITCODE-ne0){$failures.Add("Windows Time status query failed")}
  elseif($timeStatus-notmatch'(?im)^Leap Indicator:\s*0\b'){$failures.Add("Windows Time reports an unsynchronized or warning leap indicator")}
  if($timeStatus-notmatch'(?im)^Last Successful Sync Time:\s*(?!unspecified)\S'){$failures.Add("Windows Time has no recorded successful synchronization")}
}
foreach($taskName in $RequiredTaskNames){
  $task=Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
  if(-not$task){$failures.Add("Required scheduled task is missing: $taskName");continue}
  if($task.State-eq"Disabled"){$failures.Add("Required scheduled task is disabled: $taskName")}
  if($taskName-eq"Performance-Tracker-Application"){
    if($task.State-ne"Running"){$failures.Add("Performance Tracker application task is not running")}
    if($task.Settings.RestartCount-lt3){$failures.Add("Application task must have at least three bounded restart attempts")}
    if([string]$task.Settings.MultipleInstances-ne"IgnoreNew"){$failures.Add("Application task must reject duplicate instances")}
    if($task.Principal.UserId-in@("SYSTEM","NT AUTHORITY\SYSTEM","Administrator")){$failures.Add("Application task must use the dedicated non-administrator service account")}
    if(-not(@($task.Triggers)|Where-Object{$_.CimClass.CimClassName-eq"MSFT_TaskBootTrigger"})){$failures.Add("Application task has no startup trigger")}
  }
}
$result=[ordered]@{format="performance-tracker-windows-host-readiness-v1";status=if($failures.Count){"FAIL"}else{"PASS"};checkedAt=(Get-Date).ToUniversalTime().ToString("o");applicationPort=$ApplicationPort;databasePort=$DatabasePort;requiredTasks=$RequiredTaskNames;failures=$failures}
$result|ConvertTo-Json -Depth 4
if($failures.Count){throw ($failures-join[Environment]::NewLine)}
