function Resolve-PackageSid([string]$Identity){
  if($Identity-match'^S-1-'){return [Security.Principal.SecurityIdentifier]::new($Identity)}
  return ([Security.Principal.NTAccount]::new($Identity)).Translate([Security.Principal.SecurityIdentifier])
}

function Assert-NonRedirectedInstallerPath([string]$Path){
  $current=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
  while($current){
    if(($current.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw "Installer security path contains a reparse point: $($current.FullName)"}
    $parent=[IO.Path]::GetDirectoryName($current.FullName)
    if([string]::IsNullOrWhiteSpace($parent)-or$parent-eq$current.FullName){break}
    $current=Get-Item -LiteralPath $parent -Force -ErrorAction Stop
  }
}

function Assert-ProtectedPackageAcl([string]$Directory,[string[]]$Files,[string[]]$Custodians){
  if(-not$Custodians.Count){throw 'An explicit approved package custodian list is required'}
  $broad=@('S-1-1-0','S-1-5-11','S-1-5-32-545')
  $approved=@('S-1-5-18','S-1-5-32-544')
  foreach($identity in $Custodians){
    if([string]::IsNullOrWhiteSpace($identity)){throw 'Approved package custodian identities must not be empty'}
    if($identity-notmatch'^S-1-(?:\d+-)*\d+$'){throw 'Approved package custodians must be immutable Windows SID values'}
    $sid=(Resolve-PackageSid $identity).Value
    if($sid-in$broad){throw 'Broad identities cannot be approved package custodians'}
    $approved+=$sid
  }
  $approved=@($approved|Select-Object -Unique)
  Assert-NonRedirectedInstallerPath $Directory
  foreach($path in $Files){Assert-NonRedirectedInstallerPath $path}
  $directoryAcl=Get-Acl -LiteralPath $Directory
  if(-not$directoryAcl.AreAccessRulesProtected){throw 'Installer handoff directory must have protected ACL inheritance'}
  $dangerous=[Security.AccessControl.FileSystemRights]::WriteData-bor[Security.AccessControl.FileSystemRights]::CreateFiles-bor[Security.AccessControl.FileSystemRights]::AppendData-bor[Security.AccessControl.FileSystemRights]::Delete-bor[Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles-bor[Security.AccessControl.FileSystemRights]::ChangePermissions-bor[Security.AccessControl.FileSystemRights]::TakeOwnership
  foreach($path in @($Directory)+$Files){
    if(-not(Test-Path -LiteralPath $path)){throw "Installer handoff artifact is missing: $path"}
    $acl=Get-Acl -LiteralPath $path
    $owner=$acl.GetOwner([Security.Principal.SecurityIdentifier]).Value
    if($owner-notin$approved){throw "Installer handoff artifact has an unapproved owner: $path ($owner)"}
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

function Assert-InstallerApprovalRecord([object]$Record,[hashtable]$Expected){
  if($Record.format-ne'performance-tracker-install-approval-v1'){throw 'Version 1 installer approval record is required'}
  foreach($name in $Expected.Keys){
    if($name-eq'packageCustodians'){
      $actualCustodians=@($Record.$name)|ForEach-Object{([string]$_).Trim().ToUpperInvariant()}|Where-Object{$_}|Sort-Object -Unique
      $approvedCustodians=@($Expected[$name])|ForEach-Object{([string]$_).Trim().ToUpperInvariant()}|Where-Object{$_}|Sort-Object -Unique
      foreach($identity in $actualCustodians+$approvedCustodians){if($identity-notmatch'^S-1-(?:\d+-)*\d+$'){throw 'Installer approval record packageCustodians must contain immutable Windows SID values'}}
      if(-not$actualCustodians.Count-or[string]::Join("`n",$actualCustodians)-ne[string]::Join("`n",$approvedCustodians)){throw 'Installer approval record does not match approved packageCustodians'}
      continue
    }
    $actual=[string]$Record.$name
    $approved=[string]$Expected[$name]
    if([string]::IsNullOrWhiteSpace($actual)-or-not[string]::Equals($actual,$approved,[StringComparison]::OrdinalIgnoreCase)){throw "Installer approval record does not match approved $name"}
  }
}

function Invoke-WithLockedInstallerBundle([string[]]$Paths,[scriptblock]$Action){
  if(-not$Paths.Count){throw 'Installer bundle paths are required'}
  $streams=[Collections.Generic.List[IO.FileStream]]::new()
  try {
    foreach($path in $Paths){
      if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Installer handoff artifact is missing: $path"}
      Assert-NonRedirectedInstallerPath $path
      $streams.Add([IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read))
    }
    & $Action
  } finally {
    for($index=$streams.Count-1;$index-ge0;$index--){$streams[$index].Dispose()}
  }
}
