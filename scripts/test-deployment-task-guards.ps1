# Dependency-free behavioral tests. All OS operations below are mocked; no task,
# listener, application, or production file is changed.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'deployment-task-guards.ps1')
function Stop-ScheduledTask {
  param($TaskName, $ErrorAction)
  $script:stops++
  if ($script:scenario -eq 'stop-error') { throw 'stop denied' }
}
function Get-ScheduledTask {
  param($TaskName, $ErrorAction)
  $script:polls++
  if ($script:scenario -eq 'query-error') { throw 'query denied' }
  $state = 'Ready'
  if ($script:scenario -eq 'running' -or ($script:scenario -eq 'delayed' -and $script:polls -lt 3)) { $state = 'Running' }
  if ($script:scenario -eq 'queued') { $state = 'Queued' }
  [pscustomobject]@{ State = $state }
}
function Get-NetTCPConnection {
  param($State, $ErrorAction)
  if ($script:scenario -eq 'network-error') { throw 'listener query denied' }
  if ($script:scenario -eq 'orphan' -or ($script:scenario -eq 'delayed' -and $script:polls -lt 3)) {
    [pscustomobject]@{ LocalPort = 3100 }
  }
  [pscustomobject]@{ LocalPort = 5432 }
}
function Start-Sleep { param($Seconds) $script:sleeps++ }
foreach ($case in @(
  @{name='ready'; polls=1; sleeps=0; error=$null},
  @{name='delayed'; polls=3; sleeps=2; error=$null},
  @{name='stop-error'; polls=0; sleeps=0; error='stop denied'},
  @{name='query-error'; polls=1; sleeps=0; error='query denied'},
  @{name='network-error'; polls=1; sleeps=0; error='listener query denied'},
  @{name='running'; polls=30; sleeps=29; error='Application did not stop'},
  @{name='queued'; polls=30; sleeps=29; error='Application did not stop'},
  @{name='orphan'; polls=30; sleeps=29; error='Application did not stop'}
)) {
  $script:scenario=$case.name; $script:polls=0; $script:stops=0; $script:sleeps=0
  $failure=$null
  try { Stop-DeploymentApplication -TaskName 'TEST-ONLY' -Port 3100 } catch { $failure=$_.Exception.Message }
  if (($null -eq $case.error -and $null -ne $failure) -or ($null -ne $case.error -and ($null -eq $failure -or -not $failure.StartsWith($case.error)))) {
    throw "Unexpected outcome for $($case.name): $failure"
  }
  if ($script:stops -ne 1 -or $script:polls -ne $case.polls -or $script:sleeps -ne $case.sleeps) { throw "Unexpected polling for $($case.name)" }
  Write-Output "PASS $($case.name)"
}
