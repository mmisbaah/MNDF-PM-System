$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'production-acl-policy.ps1')
$testBase=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
$fixture=Join-Path $testBase ('tracker-acl-test-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture | Out-Null
$operatorSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$serviceSid='S-1-5-19' # Local Service SID; no account or service is created.
try {
  $acl=Get-Acl -LiteralPath $fixture
  $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new((Resolve-ProductionSid 'S-1-1-0'),'Read','Allow'))
  Set-Acl -LiteralPath $fixture -AclObject $acl
  Set-ExactProductionAcl -Path $fixture -ServiceAccount $serviceSid -Administrators @($operatorSid) -ServiceRights ReadAndExecute
  $result=Get-Acl -LiteralPath $fixture
  if(-not $result.AreAccessRulesProtected){throw 'Inheritance not protected'}
  $sids=@($result.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]) | ForEach-Object {$_.IdentityReference.Value} | Sort-Object -Unique)
  if($sids.Count -ne 2 -or $operatorSid -notin $sids -or $serviceSid -notin $sids){throw 'Unexpected ACL principals remain'}
  $approved=@(Resolve-ApprovedProductionAdministrators @($operatorSid) $serviceSid)
  if(@(Get-UnsafeProductionRules $result $serviceSid $true $true $approved).Count){throw 'Safe ACL rejected'}
  Write-Output 'PASS removes unrelated explicit grants and inherited rules'
  $child=Join-Path $fixture 'child'
  New-Item -ItemType Directory -Path $child | Out-Null
  $childAcl=Get-Acl -LiteralPath $child
  $childAcl.SetAccessRuleProtection($true,$true)
  $childAcl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new((Resolve-ProductionSid 'S-1-5-32-545'),'Read','Allow'))
  $childAcl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new((Resolve-ProductionSid $serviceSid),'Modify','Allow'))
  Set-Acl -LiteralPath $child -AclObject $childAcl
  $issues=@(Get-UnsafeProductionRules (Get-Acl -LiteralPath $child) $serviceSid $true $true $approved)
  if($issues.Count -ne 2){throw 'Failed to detect broad child access and service write access'}
  Write-Output 'PASS detects unsafe protected child ACLs using SIDs'
  foreach($unapproved in @('S-1-5-21-111-222-333-1001','S-1-5-21-111-222-333-2001')){
    $testAcl=[Security.AccessControl.FileSecurity]::new()
    $testAcl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new((Resolve-ProductionSid $unapproved),'Read','Allow'))
    foreach($sensitive in @($true,$false)){
      if(@(Get-UnsafeProductionRules $testAcl $serviceSid $true $sensitive $approved).Count -ne 1){throw 'Unapproved individual/group read access accepted'}
    }
  }
  Write-Output 'PASS rejects unapproved individual/group reads even on non-sensitive releases'
  foreach($invalid in @(@(),@('S-1-1-0'),@('S-1-5-11'),@('S-1-5-32-545'),@($serviceSid))){
    $rejected=$false
    try {Resolve-ApprovedProductionAdministrators $invalid $serviceSid | Out-Null}catch{$rejected=$true}
    if(-not $rejected){throw 'Unsafe or empty administrator list accepted'}
  }
  Write-Output 'PASS rejects empty, broad and service-colliding administrator lists'
  foreach($paths in @(@($fixture,$child),@($fixture,$fixture),@([IO.Path]::GetPathRoot($fixture)))){
    $rejected=$false
    try { Assert-ProductionPaths $paths } catch { $rejected=$true }
    if(-not $rejected){throw 'Unsafe target paths accepted'}
  }
  Write-Output 'PASS rejects overlapping, duplicate and root targets'
  $rejected=$false
  try {Set-ExactProductionAcl -Path $fixture -ServiceAccount $operatorSid -Administrators @($operatorSid) -ServiceRights ReadAndExecute} catch {$rejected=$true}
  if(-not $rejected){throw 'Privileged service identity accepted'}
  Write-Output 'PASS rejects service/deployment identity collision'
  $verifyArgs=@{ServiceAccount=$serviceSid;ApprovedAdministrators=@($operatorSid)}
  foreach($name in @('Release','Config','Evidence','Quarantine','Log')){
    $directory=Join-Path $fixture $name
    New-Item -ItemType Directory -Path $directory | Out-Null
    $rights=if($name -in @('Release','Config')){'ReadAndExecute'}else{'Modify'}
    Set-ExactProductionAcl -Path $directory -ServiceAccount $serviceSid -Administrators @($operatorSid) -ServiceRights $rights
    $verifyArgs[$name+'Directory']=$directory
  }
  $verifyScript=Join-Path $PSScriptRoot 'verify-production-acls.ps1'
  & $verifyScript @verifyArgs | Out-Null
  $nested=Join-Path $verifyArgs.ConfigDirectory 'nested'
  New-Item -ItemType Directory -Path $nested | Out-Null
  $leaf=Join-Path $nested 'fixture.txt'
  New-Item -ItemType File -Path $leaf | Out-Null
  $unapprovedSid='S-1-5-21-111-222-333-1001'
  $nestedAcl=Get-Acl -LiteralPath $nested
  $nestedAcl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new((Resolve-ProductionSid $unapprovedSid),'Read','ContainerInherit, ObjectInherit','None','Allow'))
  Set-Acl -LiteralPath $nested -AclObject $nestedAcl
  $inherited=@((Get-Acl -LiteralPath $leaf).GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]) | Where-Object {$_.IdentityReference.Value -eq $unapprovedSid -and $_.IsInherited})
  if(-not $inherited.Count){throw 'Inherited grant fixture was not established'}
  $rejected=$false
  try {& $verifyScript @verifyArgs | Out-Null}catch{if($_.Exception.Message -notmatch 'Unapproved access'){throw};$rejected=$true}
  if(-not $rejected){throw 'Recursive verifier accepted an unapproved nested grant'}
  Write-Output 'PASS recursive verifier accepts approved trees and rejects nested/inherited unapproved grants'
} finally {
  $resolved=[IO.Path]::GetFullPath($fixture)
  if(-not $resolved.StartsWith("$testBase\tracker-acl-test-",[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe fixture cleanup target'}
  Remove-Item -LiteralPath $resolved -Recurse -Force
}
