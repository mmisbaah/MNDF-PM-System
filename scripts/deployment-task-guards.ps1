# Stop before changing the release junction. A stopped task alone does not prove
# its child Node process has released the application port.
function Stop-DeploymentApplication {
  param([string]$TaskName, [int]$Port)
  Stop-ScheduledTask -TaskName $TaskName -ErrorAction Stop
  for ($attempt = 1; $attempt -le 30; $attempt++) {
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop
    $listeners = @(Get-NetTCPConnection -State Listen -ErrorAction Stop | Where-Object LocalPort -eq $Port)
    if ($task.State -notin @('Running', 'Queued') -and $listeners.Count -eq 0) { return }
    if ($attempt -lt 30) { Start-Sleep -Seconds 1 }
  }
  throw 'Application did not stop or release its port; release junction must not be changed'
}
