function Resolve-PackageSid([string]$Identity){
  if($Identity-match'^S-1-'){return [Security.Principal.SecurityIdentifier]::new($Identity)}
  return ([Security.Principal.NTAccount]::new($Identity)).Translate([Security.Principal.SecurityIdentifier])
}

function Assert-ProtectedPackageAcl([string]$Directory,[string[]]$Files,[string[]]$Custodians){
  if(-not$Custodians.Count){throw 'An explicit approved package custodian list is required'}
  $broad=@('S-1-1-0','S-1-5-11','S-1-5-32-545')
  $approved=@('S-1-5-18','S-1-5-32-544')
  foreach($identity in $Custodians){
    if([string]::IsNullOrWhiteSpace($identity)){throw 'Approved package custodian identities must not be empty'}
    $sid=(Resolve-PackageSid $identity).Value
    if($sid-in$broad){throw 'Broad identities cannot be approved package custodians'}
    $approved+=$sid
  }
  $approved=@($approved|Select-Object -Unique)
  $directoryAcl=Get-Acl -LiteralPath $Directory
  if(-not$directoryAcl.AreAccessRulesProtected){throw 'Installer handoff directory must have protected ACL inheritance'}
  $dangerous=[Security.AccessControl.FileSystemRights]::WriteData-bor[Security.AccessControl.FileSystemRights]::CreateFiles-bor[Security.AccessControl.FileSystemRights]::AppendData-bor[Security.AccessControl.FileSystemRights]::Delete-bor[Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles-bor[Security.AccessControl.FileSystemRights]::ChangePermissions-bor[Security.AccessControl.FileSystemRights]::TakeOwnership
  foreach($path in @($Directory)+$Files){
    if(-not(Test-Path -LiteralPath $path)){throw "Installer handoff artifact is missing: $path"}
    $acl=Get-Acl -LiteralPath $path
    foreach($rule in $acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])){
      if($rule.AccessControlType-eq'Allow'-and($rule.FileSystemRights-band$dangerous)-and$rule.IdentityReference.Value-notin$approved){throw "Installer handoff artifact has an unapproved writer: $path ($($rule.IdentityReference.Value))"}
    }
  }
}

function Assert-UnchangedInstallerBundle([hashtable]$InitialHashes){
  foreach($path in $InitialHashes.Keys){
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Installer handoff artifact disappeared during verification: $path"}
    $current=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if($current-ne$InitialHashes[$path]){throw "Installer handoff artifact changed during verification: $path"}
  }
}
