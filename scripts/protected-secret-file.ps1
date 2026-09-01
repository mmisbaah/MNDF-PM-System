. (Join-Path $PSScriptRoot 'production-acl-policy.ps1')

function Write-ProtectedSecretFile {
  param([string]$Path, [string]$Content, [string]$ServiceAccount, [string[]]$Administrators, [scriptblock]$Validate)
  $target=[IO.Path]::GetFullPath($Path)
  $parent=Split-Path -Parent $target
  Assert-ProductionPaths @($parent)
  if(-not(Test-Path -LiteralPath $parent -PathType Container)){throw 'Provision the protected configuration directory first'}
  if(Test-Path -LiteralPath $target){throw 'Refusing to overwrite an existing secret file'}
  $serviceSid=Resolve-ProductionSid $ServiceAccount
  $admins=@($Administrators | ForEach-Object { (Resolve-ProductionSid $_).Value } | Select-Object -Unique)
  $broad=@('S-1-1-0','S-1-5-11','S-1-5-32-545')
  if($serviceSid.Value -in ($admins+$broad+@('S-1-5-18','S-1-5-32-544')) -or @($admins | Where-Object {$_ -in $broad}).Count){throw 'Secret service and administrator identities must be separate and narrowly scoped'}
  $parentAcl=Get-Acl -LiteralPath $parent
  $writeRights=[Security.AccessControl.FileSystemRights]::Write -bor [Security.AccessControl.FileSystemRights]::Delete -bor [Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles -bor [Security.AccessControl.FileSystemRights]::ChangePermissions -bor [Security.AccessControl.FileSystemRights]::TakeOwnership
  foreach($rule in $parentAcl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])){
    if($rule.AccessControlType -eq 'Allow' -and $rule.IdentityReference.Value -notin $admins -and ($rule.FileSystemRights -band $writeRights)){throw 'Configuration directory has an unapproved writer; repair its ACL first'}
  }
  $security=[Security.AccessControl.FileSecurity]::new()
  $security.SetAccessRuleProtection($true,$false)
  foreach($sid in $admins){$security.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new((Resolve-ProductionSid $sid),'FullControl','Allow'))}
  $security.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($serviceSid,'Read','Allow'))
  $temporary=Join-Path $parent ('.secret-'+[guid]::NewGuid().ToString('N')+'.tmp')
  $created=$false
  try {
    # Supply the security descriptor at creation, before any secret bytes exist.
    if($PSVersionTable.PSEdition -eq 'Desktop'){
      $stream=[IO.FileStream]::new($temporary,[IO.FileMode]::CreateNew,[Security.AccessControl.FileSystemRights]::Write,[IO.FileShare]::None,4096,[IO.FileOptions]::None,$security)
    } else {
      $stream=[IO.FileSystemAclExtensions]::Create([IO.FileInfo]::new($temporary),[IO.FileMode]::CreateNew,[Security.AccessControl.FileSystemRights]::Write,[IO.FileShare]::None,4096,[IO.FileOptions]::None,$security)
    }
    $created=$true
    try {$bytes=[Text.UTF8Encoding]::new($false).GetBytes($Content);$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)} finally {$stream.Dispose()}
    & $Validate $temporary
    # Same-directory rename, no overwrite. A concurrent destination is preserved.
    [IO.File]::Move($temporary,$target)
    $created=$false
  } finally {
    if($created -and (Test-Path -LiteralPath $temporary)){Remove-Item -LiteralPath $temporary -Force}
  }
}
