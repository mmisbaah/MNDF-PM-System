function Resolve-ProductionSid([string]$Identity) {
  if ($Identity -match '^S-1-') { return [Security.Principal.SecurityIdentifier]::new($Identity) }
  return ([Security.Principal.NTAccount]::new($Identity)).Translate([Security.Principal.SecurityIdentifier])
}

function Assert-ProductionPaths($Paths) {
  $normalized = @($Paths | ForEach-Object { [IO.Path]::GetFullPath($_).TrimEnd('\') })
  foreach ($path in $normalized) {
    if ($path -eq [IO.Path]::GetPathRoot($path).TrimEnd('\')) { throw 'Filesystem roots are not valid production directories' }
    foreach ($other in $normalized) {
      if ($path.StartsWith("$other\", [StringComparison]::OrdinalIgnoreCase)) { throw 'Production directories must not overlap' }
    }
    $cursor = $path
    while ($cursor) {
      if (Test-Path -LiteralPath $cursor) {
        if ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Redirected production path rejected: $cursor" }
      }
      $cursor = Split-Path -Parent $cursor
    }
  }
  if (($normalized | ForEach-Object { $_.ToLowerInvariant() } | Select-Object -Unique).Count -ne $normalized.Count) { throw 'Production directories must be distinct' }
}

function Set-ExactProductionAcl {
  param([string]$Path, [string]$ServiceAccount, [string[]]$Administrators, [Security.AccessControl.FileSystemRights]$ServiceRights)
  $serviceSid = Resolve-ProductionSid $ServiceAccount
  $adminSids = @($Administrators | ForEach-Object { (Resolve-ProductionSid $_).Value } | Select-Object -Unique)
  if ($serviceSid.Value -in @('S-1-1-0','S-1-5-11','S-1-5-32-545','S-1-5-32-544','S-1-5-18') -or @($adminSids | Where-Object { $_ -in @('S-1-1-0','S-1-5-11','S-1-5-32-545') }).Count) { throw 'Broad identities cannot be production service or deployment accounts' }
  if ($serviceSid.Value -in $adminSids) { throw 'Service account must be separate from deployment administrators' }
  $acl = Get-Acl -LiteralPath $Path
  $acl.SetAccessRuleProtection($true, $false)
  foreach ($rule in @($acl.Access)) { $acl.RemoveAccessRuleSpecific($rule) }
  foreach ($sid in $adminSids) {
    $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new((Resolve-ProductionSid $sid), 'FullControl', 'ContainerInherit, ObjectInherit', 'None', 'Allow'))
  }
  $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($serviceSid, $ServiceRights, 'ContainerInherit, ObjectInherit', 'None', 'Allow'))
  Set-Acl -LiteralPath $Path -AclObject $acl
}

function Resolve-ApprovedProductionAdministrators([string[]]$Administrators, [string]$ServiceSid) {
  if(-not $Administrators.Count){throw 'An explicit approved deployment administrator list is required'}
  $approved=@('S-1-5-18','S-1-5-32-544')
  foreach($identity in $Administrators){
    if([string]::IsNullOrWhiteSpace($identity)){throw 'Approved administrator identities must not be empty'}
    $sid=(Resolve-ProductionSid $identity).Value
    if($sid -in @('S-1-1-0','S-1-5-11','S-1-5-32-545')){throw 'Broad identities cannot be approved administrators'}
    $approved+=$sid
  }
  if($ServiceSid -in ($approved+@('S-1-1-0','S-1-5-11','S-1-5-32-545'))){throw 'Service account must be separate and narrowly scoped'}
  return @($approved | Select-Object -Unique)
}

function Get-UnsafeProductionRules($Acl, [string]$ServiceSid, [bool]$ReadOnly, [bool]$Sensitive, [string[]]$ApprovedAdministratorSids) {
  if(-not $ApprovedAdministratorSids.Count){throw 'Approved administrator SIDs are required for ACL verification'}
  $dangerous = [Security.AccessControl.FileSystemRights]::Write -bor [Security.AccessControl.FileSystemRights]::Delete -bor [Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles -bor [Security.AccessControl.FileSystemRights]::ChangePermissions -bor [Security.AccessControl.FileSystemRights]::TakeOwnership
  foreach ($rule in $Acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier])) {
    $sid = $rule.IdentityReference.Value
    if ($rule.AccessControlType -eq 'Allow') {
      if ($sid -ne $ServiceSid -and $sid -notin $ApprovedAdministratorSids) { "Unapproved access: $sid" }
      if ($sid -eq $ServiceSid -and $ReadOnly -and ($rule.FileSystemRights -band $dangerous)) { 'Service account has write/delete/ownership rights on read-only content' }
    } elseif ($sid -eq $ServiceSid) { 'Explicit service-account deny requires operator review' }
  }
}
