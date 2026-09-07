param(
  [Parameter(Mandatory=$true)][string]$InstallerPath,
  [Parameter(Mandatory=$true)][string]$BuildRecordPath,
  [string]$ReleasePublicKey,
  [string]$NodeRuntimeDirectory,
  [ValidatePattern('^[0-9a-fA-F]{40}$')][string]$ApprovedSigningCertificateThumbprint,
  [ValidatePattern('^[0-9a-fA-F]{40}$')][string]$ApprovedTimestampCertificateThumbprint,
  [ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ApprovedCompilerSha256='0a8757031b33777e4c9cbffee40f11a5062b36d25cbe144c1db73b6102b80ad7',
  [ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ApprovedSignToolSha256,
  [ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ApprovedReleasePublicKeySha256,
  [ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ApprovedNodeRuntimeSha256='3602f2bb1a10f2cbab4c36886218a33c1ab3db87290e73b033c46c77147d0237',
  [switch]$AllowUnsignedRehearsal
)
$ErrorActionPreference='Stop'
$installer=[IO.Path]::GetFullPath($InstallerPath)
$recordPath=[IO.Path]::GetFullPath($BuildRecordPath)
if(-not(Test-Path -LiteralPath $installer -PathType Leaf)){throw 'Installer executable was not found'}
if(-not(Test-Path -LiteralPath $recordPath -PathType Leaf)){throw 'Installer build record was not found'}
$record=Get-Content -LiteralPath $recordPath -Raw|ConvertFrom-Json
if($record.format-ne'performance-tracker-installer-build-v8'){throw 'Version 8 installer provenance is required'}
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
  if($record.productionAuthorized-ne$false-or$record.authenticodeStatus-ne'NotSigned'-or$null-ne$record.recordSignatureFile-or$null-ne$record.installerSignerThumbprint-or$null-ne$record.timestampSignerThumbprint-or$null-ne$record.signToolSha256-or$null-ne$record.signToolSigner){throw 'Artifact is not a valid unsigned rehearsal bundle'}
} else {
  if($record.productionAuthorized-ne$true-or$record.authenticodeStatus-ne'Valid'){throw 'Installer provenance does not authorize production use'}
  if(-not$ApprovedSigningCertificateThumbprint){throw 'The independently approved code-signing certificate thumbprint is required'}
  if(-not$ApprovedTimestampCertificateThumbprint){throw 'The independently approved RFC 3161 timestamp certificate thumbprint is required'}
  if($record.compilerSha256-ne$ApprovedCompilerSha256.ToLowerInvariant()){throw 'Installer compiler does not match the independently approved fingerprint'}
  if(-not$ApprovedSignToolSha256){throw 'The independently approved signtool.exe SHA-256 fingerprint is required'}
  if(-not$ApprovedReleasePublicKeySha256){throw 'The independently approved release public-key SHA-256 fingerprint is required'}
  if(([string]$record.signToolSha256)-notmatch'^[0-9a-f]{64}$'-or[string]::IsNullOrWhiteSpace([string]$record.signToolSigner)){throw 'Installer provenance does not identify an approved Windows signing tool'}
  if($record.signToolSha256-ne$ApprovedSignToolSha256.ToLowerInvariant()){throw 'Windows signing tool does not match the independently approved fingerprint'}
  $signature=Get-AuthenticodeSignature -LiteralPath $installer
  if($signature.Status-ne'Valid'){throw 'Installer executable does not have a valid Authenticode signature'}
  if(-not$signature.SignerCertificate-or-not$signature.TimeStamperCertificate){throw 'Installer signature identity or RFC 3161 timestamp is missing'}
  foreach($thumbprint in @($record.installerSignerThumbprint,$record.timestampSignerThumbprint)){if(([string]$thumbprint)-notmatch'^[0-9a-f]{40,64}$'){throw 'Installer provenance contains an invalid signer fingerprint'}}
  if($signature.SignerCertificate.Thumbprint.ToLowerInvariant()-ne$record.installerSignerThumbprint-or$signature.SignerCertificate.Subject-ne$record.installerSignerSubject){throw 'Installer signer identity does not match provenance'}
  if($signature.SignerCertificate.Thumbprint-ne$ApprovedSigningCertificateThumbprint){throw 'Installer signer does not match the independently approved certificate thumbprint'}
  if($signature.TimeStamperCertificate.Thumbprint.ToLowerInvariant()-ne$record.timestampSignerThumbprint){throw 'Installer timestamp authority does not match provenance'}
  if($signature.TimeStamperCertificate.Thumbprint-ne$ApprovedTimestampCertificateThumbprint){throw 'Installer timestamp authority does not match the independently approved certificate'}
  if(-not$ReleasePublicKey-or-not(Test-Path -LiteralPath $ReleasePublicKey -PathType Leaf)){throw 'Pinned release public key is required'}
  $publicKey=[IO.Path]::GetFullPath($ReleasePublicKey)
  $actualPublicKeySha256=(Get-FileHash -LiteralPath $publicKey -Algorithm SHA256).Hash.ToLowerInvariant()
  if($actualPublicKeySha256-ne$ApprovedReleasePublicKeySha256.ToLowerInvariant()){throw 'Release public key does not match the independently approved fingerprint'}
  if($actualPublicKeySha256-ne$record.releasePublicKeySha256){throw 'Release public key fingerprint does not match installer provenance'}
  if([IO.Path]::GetFileName([string]$record.recordSignatureFile)-ne$record.recordSignatureFile){throw 'Installer provenance contains an unsafe signature filename'}
  $recordSignature=Join-Path $artifactDirectory ([string]$record.recordSignatureFile)
  if($recordSignature-ne"$recordPath.sig.json"-or-not(Test-Path -LiteralPath $recordSignature -PathType Leaf)){throw 'Installer provenance signature is missing or misplaced'}
  if(-not$NodeRuntimeDirectory){throw 'Approved portable Node.js runtime is required'}
  $node=Join-Path ([IO.Path]::GetFullPath($NodeRuntimeDirectory)) 'node.exe'
  if(-not(Test-Path -LiteralPath $node -PathType Leaf)){throw 'Approved portable Node.js runtime was not found'}
  $runtimeHash=(Get-FileHash -LiteralPath $node -Algorithm SHA256).Hash.ToLowerInvariant()
  if($runtimeHash-ne$ApprovedNodeRuntimeSha256.ToLowerInvariant()){throw 'Verification runtime does not match the independently approved fingerprint'}
  if($runtimeHash-ne$record.nodeRuntimeSha256){throw 'Verification runtime fingerprint does not match installer provenance'}
  $runtimeSignature=Get-AuthenticodeSignature -LiteralPath $node
  if($runtimeSignature.Status-ne'Valid'-or$runtimeSignature.SignerCertificate.Subject-notmatch'(^|,\s*)O=OpenJS Foundation(,|$)'){throw 'Verification runtime does not have a valid OpenJS Foundation Authenticode signature'}
  if([string]::IsNullOrWhiteSpace([string]$record.nodeRuntimeSigner)-or$runtimeSignature.SignerCertificate.Subject-ne$record.nodeRuntimeSigner){throw 'Verification runtime publisher does not match installer provenance'}
  & $node (Join-Path $PSScriptRoot 'release-signing.mjs') verify $recordPath $recordSignature $publicKey
  if($LASTEXITCODE-ne0){throw 'Installer provenance signature verification failed'}
}
Write-Output "Installer package verification passed: $actualInstallerHash"
