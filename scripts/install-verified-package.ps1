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
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ApprovedLauncherSha256,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ApprovedVerifierSha256,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ApprovedAclHelperSha256,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ApprovedReleaseSigningHelperSha256,
  [Parameter(Mandatory=$true)][string]$ApprovalRecordPath,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ApprovedApprovalRecordSha256,
  [ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ApprovedCompilerSha256='0a8757031b33777e4c9cbffee40f11a5062b36d25cbe144c1db73b6102b80ad7',
  [ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ApprovedNodeRuntimeSha256='3602f2bb1a10f2cbab4c36886218a33c1ab3db87290e73b033c46c77147d0237',
  [Parameter(Mandatory=$true)][string[]]$ApprovedPackageCustodians
)
$ErrorActionPreference='Stop'
$launcher=[IO.Path]::GetFullPath($MyInvocation.MyCommand.Path)
$verifier=Join-Path $PSScriptRoot 'verify-installer-package.ps1'
$aclHelper=Join-Path $PSScriptRoot 'installer-package-acl.ps1'
$releaseSigningHelper=Join-Path $PSScriptRoot 'release-signing.mjs'
$tools=@(
  @{Path=$launcher;Approved=$ApprovedLauncherSha256;Name='installer launcher'},
  @{Path=$verifier;Approved=$ApprovedVerifierSha256;Name='package verifier'},
  @{Path=$aclHelper;Approved=$ApprovedAclHelperSha256;Name='ACL helper'},
  @{Path=$releaseSigningHelper;Approved=$ApprovedReleaseSigningHelperSha256;Name='release-signing helper'}
)
$toolStreams=[Collections.Generic.List[IO.FileStream]]::new()
try {
  foreach($tool in $tools){
    if(-not(Test-Path -LiteralPath $tool.Path -PathType Leaf)){throw "Approved $($tool.Name) was not found"}
    $current=Get-Item -LiteralPath $tool.Path -Force
    while($current){
      if(($current.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw "Approved verification-tool path contains a reparse point: $($current.FullName)"}
      $parent=[IO.Path]::GetDirectoryName($current.FullName)
      if([string]::IsNullOrWhiteSpace($parent)-or$parent-eq$current.FullName){break}
      $current=Get-Item -LiteralPath $parent -Force
    }
    $toolStreams.Add([IO.File]::Open($tool.Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read))
  }
  foreach($tool in $tools){
    $actual=(Get-FileHash -LiteralPath $tool.Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if($actual-ne$tool.Approved.ToLowerInvariant()){throw "Approved $($tool.Name) fingerprint does not match"}
  }
  . $aclHelper
  $installer=[IO.Path]::GetFullPath($InstallerPath)
  $record=[IO.Path]::GetFullPath($BuildRecordPath)
  $signature="$record.sig.json"
  $publicKey=[IO.Path]::GetFullPath($ReleasePublicKey)
  $node=Join-Path ([IO.Path]::GetFullPath($NodeRuntimeDirectory)) 'node.exe'
  $approvalRecord=[IO.Path]::GetFullPath($ApprovalRecordPath)
  Assert-ProtectedPackageAcl ([IO.Path]::GetDirectoryName($publicKey)) @($publicKey) $ApprovedPackageCustodians
  Assert-ProtectedPackageAcl ([IO.Path]::GetDirectoryName($node)) @($node) $ApprovedPackageCustodians
  Assert-ProtectedPackageAcl ([IO.Path]::GetDirectoryName($approvalRecord)) @($approvalRecord) $ApprovedPackageCustodians
  $verification=@{
    InstallerPath=$installer;BuildRecordPath=$record;ReleasePublicKey=$publicKey;NodeRuntimeDirectory=$NodeRuntimeDirectory
    ApprovedInstallerSha256=$ApprovedInstallerSha256;ApprovedSigningCertificateThumbprint=$ApprovedSigningCertificateThumbprint
    ApprovedTimestampCertificateThumbprint=$ApprovedTimestampCertificateThumbprint;ApprovedAppVersion=$ApprovedAppVersion
    ApprovedReleaseCommit=$ApprovedReleaseCommit;ApprovedReleaseId=$ApprovedReleaseId;ApprovedCompilerSha256=$ApprovedCompilerSha256
    ApprovedSignToolSha256=$ApprovedSignToolSha256;ApprovedReleasePublicKeySha256=$ApprovedReleasePublicKeySha256
    ApprovedNodeRuntimeSha256=$ApprovedNodeRuntimeSha256;ApprovedPackageCustodians=$ApprovedPackageCustodians
  }
  Invoke-WithLockedInstallerBundle @($installer,$record,$signature,$publicKey,$node,$approvalRecord) {
    $approvalHash=(Get-FileHash -LiteralPath $approvalRecord -Algorithm SHA256).Hash.ToLowerInvariant()
    if($approvalHash-ne$ApprovedApprovalRecordSha256.ToLowerInvariant()){throw 'Installer approval record fingerprint does not match independent approval'}
    $approval=Get-Content -LiteralPath $approvalRecord -Raw|ConvertFrom-Json
    Assert-InstallerApprovalRecord $approval @{
      installerSha256=$ApprovedInstallerSha256;signingCertificateThumbprint=$ApprovedSigningCertificateThumbprint
      timestampCertificateThumbprint=$ApprovedTimestampCertificateThumbprint;version=$ApprovedAppVersion;releaseCommit=$ApprovedReleaseCommit
      releaseId=$ApprovedReleaseId;compilerSha256=$ApprovedCompilerSha256;signToolSha256=$ApprovedSignToolSha256
      releasePublicKeySha256=$ApprovedReleasePublicKeySha256;nodeRuntimeSha256=$ApprovedNodeRuntimeSha256
      launcherSha256=$ApprovedLauncherSha256;verifierSha256=$ApprovedVerifierSha256;aclHelperSha256=$ApprovedAclHelperSha256
      releaseSigningHelperSha256=$ApprovedReleaseSigningHelperSha256
      packageCustodians=$ApprovedPackageCustodians
    }
    & $verifier @verification
    $process=Start-Process -FilePath $installer -Wait -PassThru
    if($process.ExitCode-ne0){throw "Verified installer exited with code $($process.ExitCode)"}
  }
} finally {
  for($index=$toolStreams.Count-1;$index-ge0;$index--){$toolStreams[$index].Dispose()}
}
Write-Output 'Verified installer completed successfully.'
