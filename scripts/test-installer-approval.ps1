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
  Write-Output 'Installer approval ceremony tests passed.'
}finally{Remove-Item -LiteralPath $root -Recurse -Force}
