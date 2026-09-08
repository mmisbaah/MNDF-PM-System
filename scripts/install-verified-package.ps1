param(
  [Parameter(Mandatory=$true)][string]$InstallerPath,
  [Parameter(Mandatory=$true)][string]$BuildRecordPath,
  [Parameter(Mandatory=$true)][string]$ReleasePublicKey,
  [Parameter(Mandatory=$true)][string]$NodeRuntimeDirectory,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ApprovedInstallerSha256,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{40}$')][string]$ApprovedSigningCertificateThumbprint,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{40}$')][string]$ApprovedTimestampCertificateThumbprint,
  [Parameter(Mandatory=$true)][ValidatePattern('^\d+\.\d+\.\d+([.-][A-Za-z0-9.-]+)?$')][string]$ApprovedAppVersion,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{40}$')][string]$ApprovedReleaseCommit,
  [Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$')][string]$ApprovedReleaseId,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ApprovedSignToolSha256,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ApprovedReleasePublicKeySha256,
  [ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ApprovedCompilerSha256='0a8757031b33777e4c9cbffee40f11a5062b36d25cbe144c1db73b6102b80ad7',
  [ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ApprovedNodeRuntimeSha256='3602f2bb1a10f2cbab4c36886218a33c1ab3db87290e73b033c46c77147d0237',
  [Parameter(Mandatory=$true)][string[]]$ApprovedPackageCustodians
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'installer-package-acl.ps1')
$installer=[IO.Path]::GetFullPath($InstallerPath)
$record=[IO.Path]::GetFullPath($BuildRecordPath)
$signature="$record.sig.json"
$verification=@{
  InstallerPath=$installer;BuildRecordPath=$record;ReleasePublicKey=$ReleasePublicKey;NodeRuntimeDirectory=$NodeRuntimeDirectory
  ApprovedInstallerSha256=$ApprovedInstallerSha256;ApprovedSigningCertificateThumbprint=$ApprovedSigningCertificateThumbprint
  ApprovedTimestampCertificateThumbprint=$ApprovedTimestampCertificateThumbprint;ApprovedAppVersion=$ApprovedAppVersion
  ApprovedReleaseCommit=$ApprovedReleaseCommit;ApprovedReleaseId=$ApprovedReleaseId;ApprovedCompilerSha256=$ApprovedCompilerSha256
  ApprovedSignToolSha256=$ApprovedSignToolSha256;ApprovedReleasePublicKeySha256=$ApprovedReleasePublicKeySha256
  ApprovedNodeRuntimeSha256=$ApprovedNodeRuntimeSha256;ApprovedPackageCustodians=$ApprovedPackageCustodians
}
Invoke-WithLockedInstallerBundle @($installer,$record,$signature) {
  & (Join-Path $PSScriptRoot 'verify-installer-package.ps1') @verification
  $process=Start-Process -FilePath $installer -Wait -PassThru
  if($process.ExitCode-ne0){throw "Verified installer exited with code $($process.ExitCode)"}
}
Write-Output 'Verified installer completed successfully.'
