# Mock PostgreSQL utilities: never connects to or deletes a real database.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'release-database-ownership.ps1')
function createdb {
  $script:createCalls.Add(@($args))
  if($script:launchFailure){throw 'Simulated utility launch failure'}
  $global:LASTEXITCODE=$script:createExit
}
function dropdb {$script:dropCalls.Add(@($args));$global:LASTEXITCODE=$script:dropExit}
function Assert-Test([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Assert-Rejected([scriptblock]$Action){$rejected=$false;try{& $Action}catch{$rejected=$true};Assert-Test $rejected 'Expected rejection'}
$previousExit=$global:LASTEXITCODE
try {
  foreach($scenario in @('no-create','collision','launch-failure','success','later-failure','cleanup-failure','unsafe-name')){
    $script:createCalls=[Collections.Generic.List[object]]::new();$script:dropCalls=[Collections.Generic.List[object]]::new()
    $script:createExit=0;$script:dropExit=0;$script:launchFailure=$false
    $state=New-ReleaseDatabaseState 'postgresql://fixture@127.0.0.1:1/postgres'
    Assert-Test ($state.Name.Length -le 63) 'PostgreSQL identifier too long'
    $other=New-ReleaseDatabaseState $state.MaintenanceUrl
    Assert-Test ($state.Name -ne $other.Name) 'Database names must differ between runs'
    switch($scenario){
      'no-create' {Remove-OwnedReleaseDatabase $state}
      'collision' {$script:createExit=1;Assert-Rejected {New-OwnedReleaseDatabase $state};Remove-OwnedReleaseDatabase $state;Assert-Rejected {New-OwnedReleaseDatabase $state}}
      'launch-failure' {$script:launchFailure=$true;Assert-Rejected {New-OwnedReleaseDatabase $state};Remove-OwnedReleaseDatabase $state}
      'success' {New-OwnedReleaseDatabase $state;Remove-OwnedReleaseDatabase $state;Remove-OwnedReleaseDatabase $state}
      'later-failure' {try{New-OwnedReleaseDatabase $state;throw 'Simulated migration failure'}catch{}finally{Remove-OwnedReleaseDatabase $state}}
      'cleanup-failure' {New-OwnedReleaseDatabase $state;$script:dropExit=1;Assert-Rejected {Remove-OwnedReleaseDatabase $state};Assert-Test $state.Created 'Failed cleanup lost ownership state'}
      'unsafe-name' {$state.Name='production';Assert-Rejected {New-OwnedReleaseDatabase $state};$state.Created=$true;Assert-Rejected {Remove-OwnedReleaseDatabase $state}}
    }
    $expectedDrops=if($scenario -in @('success','later-failure','cleanup-failure')){1}else{0}
    Assert-Test ($script:dropCalls.Count -eq $expectedDrops) "Unexpected cleanup in $scenario"
    foreach($call in $script:dropCalls){Assert-Test ($call[-1] -ceq $state.Name -and $call[0] -eq "--maintenance-db=$($state.MaintenanceUrl)") 'Cleanup targeted a different database/server'}
    Write-Output "PASS: database ownership $scenario"
  }
  # Exercise the real gate's finally cleanup branch and result bookkeeping.
  $tokens=$null;$parseErrors=$null
  $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'release-gate.ps1'),[ref]$tokens,[ref]$parseErrors)
  Assert-Test ($parseErrors.Count -eq 0) 'Release gate syntax failed'
  $gateFunction=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Invoke-GateStep'},$true)
  . ([scriptblock]::Create($gateFunction.Extent.Text))
  $gateTry=@($ast.EndBlock.Statements | Where-Object {$_ -is [Management.Automation.Language.TryStatementAst]})[0]
  $cleanup=[scriptblock]::Create($gateTry.Finally.Statements[0].Extent.Text)
  foreach($primaryFailure in @($null,'Original validation failure')){
    $checks=[Collections.Generic.List[object]]::new()
    $databaseState=New-ReleaseDatabaseState 'postgresql://fixture@127.0.0.1:1/postgres'
    $script:createExit=0;$script:dropExit=1;$script:launchFailure=$false
    New-OwnedReleaseDatabase $databaseState
    $failure=$primaryFailure
    . $cleanup
    Assert-Test ([bool]$failure) 'Cleanup failure must fail the gate'
    if($primaryFailure){Assert-Test ($failure -eq $primaryFailure) 'Cleanup masked the original failure'}
    Assert-Test ($checks.Count -eq 1 -and $checks[0].status -eq 'FAIL') 'Cleanup failure not recorded'
    Write-Output "PASS: actual gate cleanup failure bookkeeping (prior failure: $([bool]$primaryFailure))"
  }
} finally {$global:LASTEXITCODE=$previousExit}
