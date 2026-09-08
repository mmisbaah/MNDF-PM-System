$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'installer-package-acl.ps1')
. (Join-Path $PSScriptRoot 'production-acl-policy.ps1')
$root=Join-Path ([IO.Path]::GetTempPath()) ('pt-installer-acl-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root|Out-Null
$files=@('setup.exe','setup.exe.build.json','setup.exe.build.json.sig.json')|ForEach-Object{$path=Join-Path $root $_;[IO.File]::WriteAllText($path,'test');$path}
$currentSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$readOnlySid='S-1-5-19'
try{
  $failed=$false;try{Assert-ProtectedPackageAcl $root $files @($currentSid)}catch{$failed=$_.Exception.Message-match'protected ACL inheritance'}
  if(-not$failed){throw 'Inherited handoff directory ACL was accepted'}
  Set-ExactProductionAcl -Path $root -ServiceAccount $readOnlySid -Administrators @($currentSid) -ServiceRights ReadAndExecute
  Assert-ProtectedPackageAcl $root $files @($currentSid)
  $initial=@{};foreach($file in $files){$initial[$file]=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()}
  Assert-UnchangedInstallerBundle $initial
  [IO.File]::AppendAllText($files[1],'changed')
  $failed=$false;try{Assert-UnchangedInstallerBundle $initial}catch{$failed=$_.Exception.Message-match'changed during verification'}
  if(-not$failed){throw 'Mid-verification bundle mutation was accepted'}
  [IO.File]::WriteAllText($files[1],'test')
  Remove-Item -LiteralPath $files[2]
  $failed=$false;try{Assert-UnchangedInstallerBundle $initial}catch{$failed=$_.Exception.Message-match'disappeared during verification'}
  if(-not$failed){throw 'Mid-verification bundle removal was accepted'}
  [IO.File]::WriteAllText($files[2],'test')
  $lockRejected=$false
  Invoke-WithLockedInstallerBundle $files {
    try{[IO.File]::Open($files[0],[IO.FileMode]::Open,[IO.FileAccess]::Write,[IO.FileShare]::None).Dispose()}catch{$lockRejected=$true}
    if(-not$lockRejected){throw 'Installer bundle lock permitted a concurrent writer'}
  }
  $writeAfterRelease=[IO.File]::Open($files[0],[IO.FileMode]::Open,[IO.FileAccess]::Write,[IO.FileShare]::None)
  $writeAfterRelease.Dispose()
  $failed=$false;try{Assert-ProtectedPackageAcl $root $files @('S-1-5-32-545')}catch{$failed=$_.Exception.Message-match'Broad identities'}
  if(-not$failed){throw 'Broad package custodian was accepted'}
  $acl=Get-Acl -LiteralPath $files[0]
  $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new((Resolve-PackageSid 'S-1-5-32-545'),'Write','None','None','Allow'))
  Set-Acl -LiteralPath $files[0] -AclObject $acl
  $failed=$false;try{Assert-ProtectedPackageAcl $root $files @($currentSid)}catch{$failed=$_.Exception.Message-match'unapproved writer'}
  if(-not$failed){throw 'Unapproved write access on installer artifact was accepted'}
  Write-Output 'Installer package ACL tests passed.'
}finally{
  Remove-Item -LiteralPath $root -Recurse -Force
}
