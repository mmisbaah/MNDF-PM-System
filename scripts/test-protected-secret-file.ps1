$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'protected-secret-file.ps1')
$base=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
$fixture=Join-Path $base ('tracker-secret-test-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture | Out-Null
$operatorSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$admins=@($operatorSid,'S-1-5-18','S-1-5-32-544')
$serviceSid='S-1-5-19'
$approvedAdminSids=@(Resolve-ApprovedProductionAdministrators $admins $serviceSid)
try {
  Set-ExactProductionAcl -Path $fixture -ServiceAccount $serviceSid -Administrators $admins -ServiceRights ReadAndExecute
  $target=Join-Path $fixture 'test.env'
  $arguments=@{Path=$target;Content='DUMMY=fixture-only';ServiceAccount=$serviceSid;Administrators=$admins}
  Write-ProtectedSecretFile @arguments -Validate {
    param($candidate)
    if(Test-Path -LiteralPath $target){throw 'Published before validation'}
    $acl=Get-Acl -LiteralPath $candidate
    if(-not $acl.AreAccessRulesProtected){throw 'Temporary secret has inherited access'}
    if(@(Get-UnsafeProductionRules $acl $serviceSid $true $true $approvedAdminSids).Count){throw 'Unsafe temporary secret ACL'}
    $rules=@($acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]))
    if(@($rules | Where-Object {$_.IdentityReference.Value -notin ($admins+@($serviceSid))}).Count){throw 'Unexpected temporary reader'}
    if([IO.File]::ReadAllText($candidate) -ne 'DUMMY=fixture-only'){throw 'Content not preserved'}
  }
  Write-Output 'PASS protected staging before validation and publication'
  $failed=$false
  try {Write-ProtectedSecretFile @arguments -Validate {throw 'Must not run'}} catch {$failed=$true}
  if(-not $failed -or [IO.File]::ReadAllText($target) -ne 'DUMMY=fixture-only'){throw 'Existing file not preserved'}
  Write-Output 'PASS existing destination preserved'
  $arguments.Path=Join-Path $fixture 'invalid.env'
  $failed=$false
  try {Write-ProtectedSecretFile @arguments -Validate {throw 'Validation rejected'}} catch {$failed=$true}
  if(-not $failed -or (Test-Path -LiteralPath $arguments.Path)){throw 'Invalid secret published'}
  Write-Output 'PASS validation failure does not publish'
  $raceTarget=Join-Path $fixture 'concurrent.env'
  $arguments.Path=$raceTarget
  $failed=$false
  try {Write-ProtectedSecretFile @arguments -Validate {param($candidate) [IO.File]::WriteAllText($raceTarget,'other-writer')}} catch {$failed=$true}
  if(-not $failed -or [IO.File]::ReadAllText($raceTarget) -ne 'other-writer'){throw 'Concurrent destination lost'}
  if(@(Get-ChildItem -LiteralPath $fixture -Filter '.secret-*.tmp' -Force).Count){throw 'Temporary files leaked'}
  Write-Output 'PASS competing destination survives and owned temporary files cleaned'
  & icacls $fixture /grant "*${serviceSid}:(M)" | Out-Null
  if($LASTEXITCODE -ne 0){throw 'Could not prepare unsafe-parent fixture'}
  $arguments.Path=Join-Path $fixture 'unsafe.env'
  $failed=$false
  try {Write-ProtectedSecretFile @arguments -Validate {}} catch {$failed=$true}
  if(-not $failed -or (Test-Path -LiteralPath $arguments.Path)){throw 'Unsafe parent accepted'}
  Write-Output 'PASS unsafe parent rejected'
} finally {
  if(-not ([IO.Path]::GetFullPath($fixture)).StartsWith("$base\tracker-secret-test-",[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe cleanup path'}
  Remove-Item -LiteralPath $fixture -Recurse -Force
}
