$ErrorActionPreference='Stop'
$testRoot=Join-Path ([IO.Path]::GetTempPath()) ('pt-installer-verify-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot|Out-Null
try{
  $installer=Join-Path $testRoot 'PerformanceTracker-0.1.0-test-x64-setup.exe'
  [IO.File]::WriteAllBytes($installer,[byte[]](1,2,3,4,5))
  $recordPath="$installer.build.json"
  $hash=(Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash.ToLowerInvariant()
  $record=[ordered]@{format='performance-tracker-installer-build-v5';installerFile=[IO.Path]::GetFileName($installer);recordFile=[IO.Path]::GetFileName($recordPath);recordSignatureFile=$null;sha256=$hash;releaseCommit=('a'*40);releaseId='test';version='0.1.0-test';compilerSha256=('b'*64);compilerSigner='test';nodeRuntimeVersion='v24.0.0';nodeRuntimeSha256=('c'*64);releasePublicKeySha256=('d'*64);productionHelperAllowlistSha256=('e'*64);authenticodeStatus='NotSigned';installerSignerSubject=$null;installerSignerThumbprint=$null;timestampSignerThumbprint=$null;productionAuthorized=$false;createdAt='2026-01-01T00:00:00.0000000Z'}
  $record|ConvertTo-Json|Set-Content -LiteralPath $recordPath -Encoding utf8
  & (Join-Path $PSScriptRoot 'verify-installer-package.ps1') -InstallerPath $installer -BuildRecordPath $recordPath -AllowUnsignedRehearsal
  [IO.File]::AppendAllText($installer,'tamper')
  $failed=$false
  try{& (Join-Path $PSScriptRoot 'verify-installer-package.ps1') -InstallerPath $installer -BuildRecordPath $recordPath -AllowUnsignedRehearsal}catch{$failed=$true}
  if(-not$failed){throw 'Tampered rehearsal installer was accepted'}
  [IO.File]::WriteAllBytes($installer,[byte[]](1,2,3,4,5))
  $moved=Join-Path $testRoot 'moved';New-Item -ItemType Directory -Path $moved|Out-Null
  $movedInstaller=Join-Path $moved ([IO.Path]::GetFileName($installer));$movedRecord=Join-Path $moved ([IO.Path]::GetFileName($recordPath))
  Copy-Item -LiteralPath $installer -Destination $movedInstaller;Copy-Item -LiteralPath $recordPath -Destination $movedRecord
  & (Join-Path $PSScriptRoot 'verify-installer-package.ps1') -InstallerPath $movedInstaller -BuildRecordPath $movedRecord -AllowUnsignedRehearsal
  $record.installerFile='..\escape.exe';$record|ConvertTo-Json|Set-Content -LiteralPath $movedRecord -Encoding utf8
  $failed=$false;try{& (Join-Path $PSScriptRoot 'verify-installer-package.ps1') -InstallerPath $movedInstaller -BuildRecordPath $movedRecord -AllowUnsignedRehearsal}catch{$failed=$true}
  if(-not$failed){throw 'Unsafe artifact filename was accepted'}
  Write-Output 'Installer package verification tests passed.'
}finally{Remove-Item -LiteralPath $testRoot -Recurse -Force}
