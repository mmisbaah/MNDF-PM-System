param([string]$InstallRoot='C:\PerformanceTracker')
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath($InstallRoot).TrimEnd('\')
foreach($taskName in @('Performance-Tracker-Application','Performance-Tracker-Scheduled-Jobs','Performance-Tracker-Evidence-Scanner','Performance-Tracker-Daily-Backup','Performance-Tracker-Audit-Export','Performance-Tracker-Operations-Monitor')){
  $task=Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
  if($task){
    $binding=(@($task.Actions)|ForEach-Object{"$($_.WorkingDirectory) $($_.Arguments)"})-join' '
    if($binding.IndexOf($root,[StringComparison]::OrdinalIgnoreCase)-lt0){Write-Warning "Retained $taskName because it is not bound to $root";continue}
    Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
  }
}
Write-Output 'Performance Tracker scheduled tasks were removed. Configuration, evidence, audit exports, logs, backups, and immutable releases were deliberately retained for an authorized data-custody decision.'
