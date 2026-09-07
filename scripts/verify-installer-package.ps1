param(
  [Parameter(Mandatory=$true)][string]$InstallerPath,
  [Parameter(Mandatory=$true)][string]$BuildRecordPath,
  [string]$ReleasePublicKey,
  [string]$NodeRuntimeDirectory,
  [switch]$AllowUnsignedRehearsal
)
$ErrorActionPreference='Stop'
$installer=[IO.Path]::GetFullPath($InstallerPath)
$recordPath=[IO.Path]::GetFullPath($BuildRecordPath)
if(-not(Test-Path -LiteralPath $installer -PathType Leaf)){throw 'Installer executable was not found'}
if(-not(Test-Path -LiteralPath $recordPath -PathType Leaf)){throw 'Installer build record was not found'}
$record=Get-Content -LiteralPath $recordPath -Raw|ConvertFrom-Json
if($record.format-ne'performance-tracker-installer-build-v4'){throw 'Version 4 installer provenance is required'}
$artifactDirectory=[IO.Path]::GetDirectoryName($installer)
if([IO.Path]::GetDirectoryName($recordPath)-ne$artifactDirectory){throw 'Installer and provenance record must be adjacent'}
foreach($fileName in @($record.installerFile,$record.recordFile)){
  if([string]::IsNullOrWhiteSpace([string]$fileName)-or[IO.Path]::GetFileName([string]$fileName)-ne$fileName){throw 'Installer provenance contains an unsafe artifact filename'}
}
if($record.installerFile-ne[IO.Path]::GetFileName($installer)-or$record.recordFile-ne[IO.Path]::GetFileName($recordPath)){throw 'Installer provenance filenames do not match the supplied artifacts'}
foreach($hash in @($record.sha256,$record.compilerSha256,$record.nodeRuntimeSha256,$record.releasePublicKeySha256,$record.productionHelperAllowlistSha256)){
  if(([string]$hash)-notmatch'^[0-9a-f]{64}$'){throw 'Installer provenance contains an invalid fingerprint'}
}
if(([string]$record.releaseCommit)-notmatch'^[0-9a-f]{40}$'){throw 'Installer provenance contains an invalid source commit'}
$actualInstallerHash=(Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash.ToLowerInvariant()
if($actualInstallerHash-ne$record.sha256){throw 'Installer executable hash does not match its provenance record'}
if($AllowUnsignedRehearsal){
  if($record.productionAuthorized-ne$false-or$record.authenticodeStatus-ne'NotSigned'-or$null-ne$record.recordSignatureFile){throw 'Artifact is not a valid unsigned rehearsal bundle'}
} else {
  if($record.productionAuthorized-ne$true-or$record.authenticodeStatus-ne'Valid'){throw 'Installer provenance does not authorize production use'}
  $signature=Get-AuthenticodeSignature -LiteralPath $installer
  if($signature.Status-ne'Valid'){throw 'Installer executable does not have a valid Authenticode signature'}
  if(-not$ReleasePublicKey-or-not(Test-Path -LiteralPath $ReleasePublicKey -PathType Leaf)){throw 'Pinned release public key is required'}
  $publicKey=[IO.Path]::GetFullPath($ReleasePublicKey)
  if((Get-FileHash -LiteralPath $publicKey -Algorithm SHA256).Hash.ToLowerInvariant()-ne$record.releasePublicKeySha256){throw 'Release public key fingerprint does not match installer provenance'}
  if([IO.Path]::GetFileName([string]$record.recordSignatureFile)-ne$record.recordSignatureFile){throw 'Installer provenance contains an unsafe signature filename'}
  $recordSignature=Join-Path $artifactDirectory ([string]$record.recordSignatureFile)
  if($recordSignature-ne"$recordPath.sig.json"-or-not(Test-Path -LiteralPath $recordSignature -PathType Leaf)){throw 'Installer provenance signature is missing or misplaced'}
  if(-not$NodeRuntimeDirectory){throw 'Approved portable Node.js runtime is required'}
  $node=Join-Path ([IO.Path]::GetFullPath($NodeRuntimeDirectory)) 'node.exe'
  if(-not(Test-Path -LiteralPath $node -PathType Leaf)){throw 'Approved portable Node.js runtime was not found'}
  $runtimeHash=(Get-FileHash -LiteralPath $node -Algorithm SHA256).Hash.ToLowerInvariant()
  if($runtimeHash-ne$record.nodeRuntimeSha256){throw 'Verification runtime fingerprint does not match installer provenance'}
  & $node (Join-Path $PSScriptRoot 'release-signing.mjs') verify $recordPath $recordSignature $publicKey
  if($LASTEXITCODE-ne0){throw 'Installer provenance signature verification failed'}
}
Write-Output "Installer package verification passed: $actualInstallerHash"
