# Execute the real lint gate statements with a mocked npm; no builds or databases.
$ErrorActionPreference='Stop'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'release-gate.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Release gate syntax is invalid'}
$gateFunction=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Invoke-GateStep'},$true)
. ([scriptblock]::Create($gateFunction.Extent.Text))
$calls=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Invoke-GateStep'},$true))
if($calls[0].CommandElements[1].Value -ne 'Lint progress regression' -or $calls[1].CommandElements[1].Value -ne 'ESLint'){throw 'Both lint checks must precede all build, packaging and deployment checks'}
$lintSequence=[scriptblock]::Create($calls[0].Extent.Text+"`n"+$calls[1].Extent.Text+"`n"+'$script:reachedLaterChecks=$true')
function npm {
  param([string]$Verb,[string]$Name)
  if($Verb -ne 'run'){throw 'Unexpected npm invocation'}
  $script:invocations.Add($Name)
  $global:LASTEXITCODE=if($Name -eq $script:failingCommand){$script:failureCode}else{0}
}
$previousExitCode=$global:LASTEXITCODE
try {
  foreach($scenario in @(
    @{command='';code=0;count=2},
    @{command='lint:progress:test';code=1;count=1},
    @{command='lint';code=1;count=2},
    @{command='lint';code=2;count=2}
  )){
    $checks=[Collections.Generic.List[object]]::new()
    $script:invocations=[Collections.Generic.List[string]]::new()
    $script:failingCommand=$scenario.command
    $script:failureCode=$scenario.code
    $script:reachedLaterChecks=$false
    $failed=$false
    try {& $lintSequence}catch{$failed=$true}
    if($failed -ne [bool]$scenario.command){throw 'Unexpected gate outcome'}
    if($script:reachedLaterChecks -eq $failed){throw 'Failure did not stop later checks'}
    if($checks.Count -ne $scenario.count -or $script:invocations.Count -ne $scenario.count){throw 'Incorrect executed check count'}
    if($checks[$checks.Count-1].status -ne $(if($failed){'FAIL'}else{'PASS'})){throw 'Incorrect recorded gate status'}
    Write-Output "PASS: lint gate scenario '$($scenario.command)' exit $($scenario.code)"
  }
} finally {$global:LASTEXITCODE=$previousExitCode}
