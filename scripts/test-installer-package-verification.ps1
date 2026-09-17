$ErrorActionPreference='Stop'
$testRoot=Join-Path ([IO.Path]::GetTempPath()) ('pt-installer-verify-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot|Out-Null
try{
  $installer=Join-Path $testRoot 'PerformanceTracker-0.1.0-test-x64-setup.exe'
  [IO.File]::WriteAllBytes($installer,[byte[]](1,2,3,4,5))
  $recordPath="$installer.build.json"
  $hash=(Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash.ToLowerInvariant()
  $record=[ordered]@{format='performance-tracker-installer-build-v9';installerFile=[IO.Path]::GetFileName($installer);recordFile=[IO.Path]::GetFileName($recordPath);recordSignatureFile=$null;sha256=$hash;releaseCommit=('a'*40);releaseId='test';version='0.1.0-test';compilerSha256=('b'*64);compilerSigner='test';signToolSha256=$null;signToolSigner=$null;nodeRuntimeVersion='v24.0.0';nodeRuntimeSha256=('c'*64);nodeRuntimeSigner='CN=OpenJS Foundation, O=OpenJS Foundation';releasePublicKeySha256=('d'*64);productionHelperAllowlistSha256=('e'*64);releaseCandidateAttestationSha256=$null;releaseCandidateAttestationSignatureSha256=$null;authenticodeStatus='NotSigned';installerSignerSubject=$null;installerSignerThumbprint=$null;timestampSignerThumbprint=$null;productionAuthorized=$false;createdAt='2026-01-01T00:00:00.0000000Z'}
  $record|ConvertTo-Json|Set-Content -LiteralPath $recordPath -Encoding utf8
  & (Join-Path $PSScriptRoot 'verify-installer-package.ps1') -InstallerPath $installer -BuildRecordPath $recordPath -AllowUnsignedRehearsal
  $record.productionAuthorized=$true;$record.authenticodeStatus='Valid';$record|ConvertTo-Json|Set-Content -LiteralPath $recordPath -Encoding utf8
  $failed=$false;try{& (Join-Path $PSScriptRoot 'verify-installer-package.ps1') -InstallerPath $installer -BuildRecordPath $recordPath}catch{$failed=$_.Exception.Message-match'approved installer SHA-256'}
  if(-not$failed){throw 'Production verification accepted a missing approved installer fingerprint'}
  $failed=$false;try{& (Join-Path $PSScriptRoot 'verify-installer-package.ps1') -InstallerPath $installer -BuildRecordPath $recordPath -ApprovedInstallerSha256 ('0'*64)}catch{$failed=$_.Exception.Message-match'Installer executable does not match'}
  if(-not$failed){throw 'Production verification accepted a different approved installer fingerprint'}
  $failed=$false;try{& (Join-Path $PSScriptRoot 'verify-installer-package.ps1') -InstallerPath $installer -BuildRecordPath $recordPath -ApprovedInstallerSha256 $hash}catch{$failed=$_.Exception.Message-match'approved code-signing certificate'}
  if(-not$failed){throw 'Production verification accepted a missing approved signer thumbprint'}
  $failed=$false;try{& (Join-Path $PSScriptRoot 'verify-installer-package.ps1') -InstallerPath $installer -BuildRecordPath $recordPath -ApprovedInstallerSha256 $hash -ApprovedSigningCertificateThumbprint ('f'*40)}catch{$failed=$_.Exception.Message-match'approved RFC 3161 timestamp certificate'}
  if(-not$failed){throw 'Production verification accepted a missing approved timestamp certificate'}
  $failed=$false;try{& (Join-Path $PSScriptRoot 'verify-installer-package.ps1') -InstallerPath $installer -BuildRecordPath $recordPath -ApprovedInstallerSha256 $hash -ApprovedSigningCertificateThumbprint ('f'*40) -ApprovedTimestampCertificateThumbprint ('2'*40)}catch{$failed=$_.Exception.Message-match'approved application version'}
  if(-not$failed){throw 'Production verification accepted a missing approved application version'}
  $failed=$false;try{& (Join-Path $PSScriptRoot 'verify-installer-package.ps1') -InstallerPath $installer -BuildRecordPath $recordPath -ApprovedInstallerSha256 $hash -ApprovedSigningCertificateThumbprint ('f'*40) -ApprovedTimestampCertificateThumbprint ('2'*40) -ApprovedAppVersion '9.9.9'}catch{$failed=$_.Exception.Message-match'Installer version does not match'}
  if(-not$failed){throw 'Production verification accepted a different approved application version'}
  $failed=$false;try{& (Join-Path $PSScriptRoot 'verify-installer-package.ps1') -InstallerPath $installer -BuildRecordPath $recordPath -ApprovedInstallerSha256 $hash -ApprovedSigningCertificateThumbprint ('f'*40) -ApprovedTimestampCertificateThumbprint ('2'*40) -ApprovedAppVersion '0.1.0-test'}catch{$failed=$_.Exception.Message-match'approved release commit'}
  if(-not$failed){throw 'Production verification accepted a missing approved release commit'}
  $failed=$false;try{& (Join-Path $PSScriptRoot 'verify-installer-package.ps1') -InstallerPath $installer -BuildRecordPath $recordPath -ApprovedInstallerSha256 $hash -ApprovedSigningCertificateThumbprint ('f'*40) -ApprovedTimestampCertificateThumbprint ('2'*40) -ApprovedAppVersion '0.1.0-test' -ApprovedReleaseCommit ('9'*40)}catch{$failed=$_.Exception.Message-match'Installer source commit does not match'}
  if(-not$failed){throw 'Production verification accepted a different approved release commit'}
  $failed=$false;try{& (Join-Path $PSScriptRoot 'verify-installer-package.ps1') -InstallerPath $installer -BuildRecordPath $recordPath -ApprovedInstallerSha256 $hash -ApprovedSigningCertificateThumbprint ('f'*40) -ApprovedTimestampCertificateThumbprint ('2'*40) -ApprovedAppVersion '0.1.0-test' -ApprovedReleaseCommit ('a'*40)}catch{$failed=$_.Exception.Message-match'approved release identifier'}
  if(-not$failed){throw 'Production verification accepted a missing approved release identifier'}
  $failed=$false;try{& (Join-Path $PSScriptRoot 'verify-installer-package.ps1') -InstallerPath $installer -BuildRecordPath $recordPath -ApprovedInstallerSha256 $hash -ApprovedSigningCertificateThumbprint ('f'*40) -ApprovedTimestampCertificateThumbprint ('2'*40) -ApprovedAppVersion '0.1.0-test' -ApprovedReleaseCommit ('a'*40) -ApprovedReleaseId 'different'}catch{$failed=$_.Exception.Message-match'Installer release identifier does not match'}
  if(-not$failed){throw 'Production verification accepted a different approved release identifier'}
  $record.releaseCandidateAttestationSha256=('6'*64);$record.releaseCandidateAttestationSignatureSha256=('7'*64);$record|ConvertTo-Json|Set-Content -LiteralPath $recordPath -Encoding utf8
  $failed=$false;try{& (Join-Path $PSScriptRoot 'verify-installer-package.ps1') -InstallerPath $installer -BuildRecordPath $recordPath -ApprovedInstallerSha256 $hash -ApprovedSigningCertificateThumbprint ('f'*40) -ApprovedTimestampCertificateThumbprint ('2'*40) -ApprovedAppVersion '0.1.0-test' -ApprovedReleaseCommit ('a'*40) -ApprovedReleaseId 'test' -ApprovedCompilerSha256 ('b'*64)}catch{$failed=$_.Exception.Message-match'approved signtool\.exe'}
  if(-not$failed){throw 'Production verification accepted a missing approved signing-tool fingerprint'}
  $record.signToolSha256=('1'*64);$record.signToolSigner='Microsoft';$record|ConvertTo-Json|Set-Content -LiteralPath $recordPath -Encoding utf8
  $failed=$false;try{& (Join-Path $PSScriptRoot 'verify-installer-package.ps1') -InstallerPath $installer -BuildRecordPath $recordPath -ApprovedInstallerSha256 $hash -ApprovedSigningCertificateThumbprint ('f'*40) -ApprovedTimestampCertificateThumbprint ('2'*40) -ApprovedAppVersion '0.1.0-test' -ApprovedReleaseCommit ('a'*40) -ApprovedReleaseId 'test' -ApprovedCompilerSha256 ('b'*64) -ApprovedSignToolSha256 ('1'*64)}catch{$failed=$_.Exception.Message-match'approved release public-key'}
  if(-not$failed){throw 'Production verification accepted a missing approved release-key fingerprint'}
  $record.signToolSha256=$null;$record.signToolSigner=$null;$record.releaseCandidateAttestationSha256=$null;$record.releaseCandidateAttestationSignatureSha256=$null;$record|ConvertTo-Json|Set-Content -LiteralPath $recordPath -Encoding utf8
  $record.productionAuthorized=$false;$record.authenticodeStatus='NotSigned';$record|ConvertTo-Json|Set-Content -LiteralPath $recordPath -Encoding utf8
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
