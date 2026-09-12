# Local regression only: no real services, databases, credentials or release links.
$ErrorActionPreference='Stop'
if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){throw 'Deployment regression gate requires Windows for real filesystem ACL tests'}
$nodeVersion=& node -p 'process.versions.node'
if($LASTEXITCODE -ne 0 -or [int]($nodeVersion.Split('.')[0]) -lt 22){throw 'Node.js 22 or newer is required'}
$started=(Get-Date).ToUniversalTime()
$checks=[Collections.Generic.List[object]]::new()
function Invoke-DeploymentRegression([string]$Name,[scriptblock]$Action){
  $watch=[Diagnostics.Stopwatch]::StartNew()
  try {
    & $Action
    $checks.Add([ordered]@{name=$Name;status='PASS';seconds=[math]::Round($watch.Elapsed.TotalSeconds,2)})
  } catch {
    $checks.Add([ordered]@{name=$Name;status='FAIL';seconds=[math]::Round($watch.Elapsed.TotalSeconds,2)})
    throw "Deployment regression failed: $Name. $($_.Exception.Message)"
  } finally {$watch.Stop()}
}
$passed=$false
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
  Invoke-DeploymentRegression 'PowerShell script syntax' {
    $installerRoot=Join-Path (Split-Path $PSScriptRoot -Parent) 'installer'
    foreach($file in @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1')+@(Get-ChildItem -LiteralPath $installerRoot -Filter '*.ps1' -Recurse)){
      $tokens=$null;$errors=$null
      [Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)|Out-Null
      if($errors.Count){throw "Syntax errors in $($file.Name)"}
    }
  }
  foreach($name in @('test-release-database-ownership.ps1','test-release-lint-gate.ps1','test-deployment-task-guards.ps1','test-deployment-journal.ps1','test-promotion-rollback-rehearsal.ps1','test-promotion-rehearsal-plan.ps1','test-unhealthy-rehearsal-release.ps1','test-staging-rehearsal-bundle.ps1','test-staging-rehearsal-bundle-verification.ps1','test-staging-rehearsal-cleanup.ps1','test-staging-host-readiness.ps1','test-production-acls.ps1','test-protected-secret-file.ps1','test-serialize-production-env.ps1','test-release-source-check.ps1','test-installer-contract.ps1','test-installer-approval.ps1','test-installer-rehearsal.ps1','test-installer-package-acl.ps1','test-installer-package-verification.ps1','test-installer-launcher-integrity.ps1','test-node-runtime-resolution.ps1')){
    Invoke-DeploymentRegression $name {
      $global:LASTEXITCODE=0
      & (Join-Path $PSScriptRoot $name)
      if($LASTEXITCODE -ne 0){throw 'A native test process returned a nonzero exit code'}
    }
  }
  Invoke-DeploymentRegression 'Package, signing and configuration Node regressions' {
    & node --test scripts/health-contract.test.mjs scripts/materialize-standalone.test.mjs scripts/next-config.test.mjs scripts/release-build-provenance.test.mjs scripts/release-integrity.test.mjs scripts/release-signing.test.mjs scripts/validate-production-env.test.mjs
    if($LASTEXITCODE -ne 0){throw 'Node regression suite failed'}
  }
  Invoke-DeploymentRegression 'Signature self-test' {
    & node scripts/release-signing.mjs selftest
    if($LASTEXITCODE -ne 0){throw 'Signature self-test failed'}
  }
  $passed=$true
} finally {
  Pop-Location
  [ordered]@{format='performance-tracker-deployment-regression-v1';status=if($passed){'PASS'}else{'FAIL'};startedAt=$started.ToString('o');completedAt=(Get-Date).ToUniversalTime().ToString('o');powershell=$PSVersionTable.PSVersion.ToString();node=$nodeVersion;checks=@($checks.ToArray());productionRehearsal=$false}|ConvertTo-Json -Depth 5
}
