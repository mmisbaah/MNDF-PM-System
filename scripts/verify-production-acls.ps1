param(
  [Parameter(Mandatory=$true)][string]$ReleaseDirectory,
  [Parameter(Mandatory=$true)][string]$ConfigDirectory,
  [Parameter(Mandatory=$true)][string]$EvidenceDirectory,
  [Parameter(Mandatory=$true)][string]$QuarantineDirectory,
  [Parameter(Mandatory=$true)][string]$LogDirectory,
  [Parameter(Mandatory=$true)][string]$ServiceAccount,
  [Parameter(Mandatory=$true)][string[]]$ApprovedAdministrators
)
$ErrorActionPreference="Stop"
. (Join-Path $PSScriptRoot 'production-acl-policy.ps1')
$paths=[ordered]@{release=[IO.Path]::GetFullPath($ReleaseDirectory);config=[IO.Path]::GetFullPath($ConfigDirectory);evidence=[IO.Path]::GetFullPath($EvidenceDirectory);quarantine=[IO.Path]::GetFullPath($QuarantineDirectory);logs=[IO.Path]::GetFullPath($LogDirectory)}
Assert-ProductionPaths $paths.Values
$serviceSid=(Resolve-ProductionSid $ServiceAccount).Value
$approvedAdminSids=@(Resolve-ApprovedProductionAdministrators $ApprovedAdministrators $serviceSid)
$failures=[Collections.Generic.List[string]]::new()
$broad='^(Everyone|BUILTIN\\Users|NT AUTHORITY\\Authenticated Users|S-1-1-0|S-1-5-11)$'
$dangerous=[Security.AccessControl.FileSystemRights]::WriteData-bor[Security.AccessControl.FileSystemRights]::CreateFiles-bor[Security.AccessControl.FileSystemRights]::AppendData-bor[Security.AccessControl.FileSystemRights]::Delete-bor[Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles-bor[Security.AccessControl.FileSystemRights]::ChangePermissions-bor[Security.AccessControl.FileSystemRights]::TakeOwnership
foreach($entry in $paths.GetEnumerator()){
  if(-not(Test-Path -LiteralPath $entry.Value -PathType Container)){$failures.Add("Protected directory is missing: $($entry.Value)");continue}
  $acl=Get-Acl -LiteralPath $entry.Value
  $pending=[Collections.Generic.Stack[string]]::new()
  $pending.Push($entry.Value)
  while($pending.Count){
    $path=$pending.Pop()
    $item=Get-Item -LiteralPath $path -Force
    if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){$failures.Add("Redirected child rejected: $path");continue}
    $childAcl=Get-Acl -LiteralPath $path
    foreach($issue in @(Get-UnsafeProductionRules $childAcl $serviceSid ($entry.Key -in @('release','config')) ($entry.Key -in @('config','evidence','quarantine','logs')) $approvedAdminSids)){$failures.Add("$path`: $issue")}
    if($item.PSIsContainer){foreach($child in Get-ChildItem -LiteralPath $path -Force){$pending.Push($child.FullName)}}
  }
  if(-not$acl.AreAccessRulesProtected){$failures.Add("ACL inheritance remains enabled: $($entry.Value)")}
  $serviceRights=[Security.AccessControl.FileSystemRights]0
  foreach($rule in $acl.Access){
    $identity=$rule.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value
    if($identity-eq$serviceSid-and$rule.AccessControlType-eq'Allow'){$serviceRights=$serviceRights-bor$rule.FileSystemRights}
    if($identity-match$broad-and$rule.AccessControlType-eq'Allow'){
      if($entry.Key-in@('config','evidence','quarantine')-or($rule.FileSystemRights-band$dangerous)){$failures.Add("Broad access is present on $($entry.Value): $identity $($rule.FileSystemRights)")}
    }
  }
  if($serviceRights-eq0){$failures.Add("Dedicated service account has no explicit access: $($entry.Value)")}
  elseif($entry.Key-in@('release','config')){
    if(($serviceRights-band[Security.AccessControl.FileSystemRights]::ReadAndExecute)-ne[Security.AccessControl.FileSystemRights]::ReadAndExecute){$failures.Add("Service account lacks read/execute access: $($entry.Value)")}
    if($serviceRights-band$dangerous){$failures.Add("Service account has write/delete/ownership rights on read-only path: $($entry.Value)")}
  }elseif(($serviceRights-band[Security.AccessControl.FileSystemRights]::Modify)-ne[Security.AccessControl.FileSystemRights]::Modify){$failures.Add("Service account lacks required modify access: $($entry.Value)")}
}
$result=[ordered]@{format="performance-tracker-acl-verification-v1";status=if($failures.Count){'FAIL'}else{'PASS'};checkedAt=(Get-Date).ToUniversalTime().ToString('o');serviceAccount=$ServiceAccount;approvedAdministratorSids=$approvedAdminSids;paths=$paths;failures=$failures}
$result|ConvertTo-Json -Depth 4
if($failures.Count){throw ($failures-join[Environment]::NewLine)}
