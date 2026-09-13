$ErrorActionPreference='Stop'
$root=Join-Path ([IO.Path]::GetTempPath()) ('pt-approval-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory $root|Out-Null
try{
  $output=Join-Path $root 'approval.json';$h='a'*64;$t='b'*40;$c='c'*40
  $args=@{OutputPath=$output;ApprovedBySid='S-1-5-21-1';InstallerSha256=$h;SigningCertificateThumbprint=$t;TimestampCertificateThumbprint=$c;Version='1.2.3';ReleaseCommit=('d'*40);ReleaseId='release-1';CompilerSha256=$h;SignToolSha256=$h;ReleasePublicKeySha256=$h;NodeRuntimeSha256=$h;LauncherSha256=$h;VerifierSha256=$h;AclHelperSha256=$h;ReleaseSigningHelperSha256=$h;PackageCustodians=@('S-1-5-21-2','S-1-5-18');ValidDays=7}
  & (Join-Path $PSScriptRoot 'new-installer-approval.ps1') @args|Out-Null
  $record=Get-Content $output -Raw|ConvertFrom-Json
  if($record.format-ne'performance-tracker-install-approval-v1'-or$record.approvedBySid-ne'S-1-5-21-1'-or@($record.packageCustodians).Count-ne2){throw 'Generated approval record is incomplete'}
  $failed=$false;try{& (Join-Path $PSScriptRoot 'new-installer-approval.ps1') @args|Out-Null}catch{$failed=$_.Exception.Message-match'already exists'}
  if(-not$failed){throw 'Approval generator overwrote an existing ceremony record'}
  . (Join-Path $PSScriptRoot 'installer-package-acl.ps1')
  $expired=Get-Content $output -Raw|ConvertFrom-Json;$expired.approvedAtUtc=[DateTimeOffset]::UtcNow.AddDays(-8).ToString('o');$expired.expiresAtUtc=[DateTimeOffset]::UtcNow.AddDays(-1).ToString('o')
  $failed=$false;try{Assert-InstallerApprovalRecord $expired @{}}catch{$failed=$_.Exception.Message-match'expired'}
  if(-not$failed){throw 'Expired installer approval was accepted'}
  $record.PSObject.Properties.Add([psnoteproperty]::new('unexpected','value'))
  $failed=$false;try{Assert-InstallerApprovalRecord $record @{}}catch{$failed=$_.Exception.Message-match'schema'}
  if(-not$failed){throw 'Unknown installer approval field was accepted'}
  $record=Get-Content $output -Raw|ConvertFrom-Json;$record.PSObject.Properties.Remove('releaseId')
  $failed=$false;try{Assert-InstallerApprovalRecord $record @{}}catch{$failed=$_.Exception.Message-match'schema'}
  if(-not$failed){throw 'Incomplete installer approval schema was accepted'}
  $acceptance=[pscustomobject][ordered]@{format='performance-tracker-rehearsal-acceptance-v1';decision='GO';decisionReason='All attended rehearsal safeguards passed.';authorizedAt=[DateTimeOffset]::UtcNow.ToString('o');host='STAGING-01';authorizerSid='S-1-5-21-1';rehearsalOperatorSid='S-1-5-21-2';releaseId='release-1';releaseCommit=('d'*40);installerSha256=$h;installerApprovalSha256=$h;finalEvidenceManifestSha256=$h;evidencePublicKeySha256=$h;acceptancePublicKeySha256=$h}
  Assert-RehearsalAcceptanceRecord $acceptance @{releaseId='release-1';releaseCommit=('d'*40);installerSha256=$h;authorizerSid='S-1-5-21-1'}
  $acceptance.decision='NO_GO';$failed=$false;try{Assert-RehearsalAcceptanceRecord $acceptance @{}}catch{$failed=$_.Exception.Message-match'signed GO'}
  if(-not$failed){throw 'NO_GO rehearsal acceptance was accepted for production installation'}
  $acceptance.decision='GO';$failed=$false;try{Assert-RehearsalAcceptanceRecord $acceptance @{releaseId='another-release'}}catch{$failed=$_.Exception.Message-match'releaseId'}
  if(-not$failed){throw 'Rehearsal acceptance for another release was accepted'}
  $acceptance.rehearsalOperatorSid=$acceptance.authorizerSid;$failed=$false;try{Assert-RehearsalAcceptanceRecord $acceptance @{}}catch{$failed=$_.Exception.Message-match'two-person'}
  if(-not$failed){throw 'Single-account rehearsal acceptance was accepted'}
  $preflight=[pscustomobject][ordered]@{format='performance-tracker-install-preflight-v1';status='PASS';checkedAt=[DateTimeOffset]::UtcNow.ToString('o');releaseId='release-1';releaseCommit=('d'*40);appVersion='1.2.3';installerSha256=$h;installerApprovalSha256=$h;rehearsalAcceptanceSha256=$h;acceptancePublicKeySha256=$h;signingCertificateThumbprint=$t;timestampCertificateThumbprint=$c;compilerSha256=$h;signToolSha256=$h;releasePublicKeySha256=$h;nodeRuntimeSha256=$h;launcherSha256=$h;verifierSha256=$h;aclHelperSha256=$h;releaseSigningHelperSha256=$h;packageCustodiansSha256=$h;verificationMode='NON_ELEVATED_PREFLIGHT';containsSecrets=$false;installerLaunched=$false}
  Assert-InstallPreflightReport $preflight @{releaseId='release-1';releaseCommit=('d'*40);installerSha256=$h}
  $preflight.installerSha256=('0'*64);$failed=$false;try{Assert-InstallPreflightReport $preflight @{installerSha256=$h}}catch{$failed=$_.Exception.Message-match'installerSha256'}
  if(-not$failed){throw 'Preflight report for another installer was accepted'}
  $preflight.installerSha256=$h;$preflight.checkedAt=[DateTimeOffset]::UtcNow.AddHours(-25).ToString('o');$failed=$false;try{Assert-InstallPreflightReport $preflight @{}}catch{$failed=$_.Exception.Message-match'expired'}
  if(-not$failed){throw 'Expired installation preflight report was accepted'}
  $preflight.checkedAt=[DateTimeOffset]::UtcNow.ToString('o');$preflight.installerLaunched=$true;$failed=$false;try{Assert-InstallPreflightReport $preflight @{}}catch{$failed=$_.Exception.Message-match'non-elevated'}
  if(-not$failed){throw 'Preflight report claiming an installer launch was accepted'}
  Write-Output 'Installer approval ceremony tests passed.'
}finally{Remove-Item -LiteralPath $root -Recurse -Force}
