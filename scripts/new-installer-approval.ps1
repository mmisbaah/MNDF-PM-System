param(
  [Parameter(Mandatory=$true)][string]$OutputPath,
  [Parameter(Mandatory=$true)][ValidatePattern('^S-1-(?:\d+-)*\d+$')][string]$ApprovedBySid,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$InstallerSha256,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{40}$')][string]$SigningCertificateThumbprint,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{40}$')][string]$TimestampCertificateThumbprint,
  [Parameter(Mandatory=$true)][ValidatePattern('^\d+\.\d+\.\d+([.-][A-Za-z0-9.-]+)?$')][string]$Version,[Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{40}$')][string]$ReleaseCommit,
  [Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$')][string]$ReleaseId,[Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$CompilerSha256,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$SignToolSha256,[Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ReleasePublicKeySha256,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$NodeRuntimeSha256,[Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$LauncherSha256,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$VerifierSha256,[Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$AclHelperSha256,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ReleaseSigningHelperSha256,[Parameter(Mandatory=$true)][string[]]$PackageCustodians,
  [ValidateRange(1,14)][int]$ValidDays=14
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'installer-package-acl.ps1')
$custodians=@($PackageCustodians|ForEach-Object{([string]$_).Trim().ToUpperInvariant()}|Sort-Object -Unique)
foreach($identity in $custodians){if($identity-notmatch'^S-1-(?:\d+-)*\d+$'){throw 'Package custodians must be immutable Windows SID values'}}
if(-not$custodians.Count){throw 'At least one package custodian SID is required'}
$approvedAt=[DateTimeOffset]::UtcNow
$record=[ordered]@{format='performance-tracker-install-approval-v1';approvedBySid=$ApprovedBySid.ToUpperInvariant();approvedAtUtc=$approvedAt.ToString('o');expiresAtUtc=$approvedAt.AddDays($ValidDays).ToString('o');installerSha256=$InstallerSha256.ToLowerInvariant();signingCertificateThumbprint=$SigningCertificateThumbprint.ToUpperInvariant();timestampCertificateThumbprint=$TimestampCertificateThumbprint.ToUpperInvariant();version=$Version;releaseCommit=$ReleaseCommit.ToLowerInvariant();releaseId=$ReleaseId;compilerSha256=$CompilerSha256.ToLowerInvariant();signToolSha256=$SignToolSha256.ToLowerInvariant();releasePublicKeySha256=$ReleasePublicKeySha256.ToLowerInvariant();nodeRuntimeSha256=$NodeRuntimeSha256.ToLowerInvariant();launcherSha256=$LauncherSha256.ToLowerInvariant();verifierSha256=$VerifierSha256.ToLowerInvariant();aclHelperSha256=$AclHelperSha256.ToLowerInvariant();releaseSigningHelperSha256=$ReleaseSigningHelperSha256.ToLowerInvariant();packageCustodians=$custodians}
$expected=@{};foreach($name in @('installerSha256','signingCertificateThumbprint','timestampCertificateThumbprint','version','releaseCommit','releaseId','compilerSha256','signToolSha256','releasePublicKeySha256','nodeRuntimeSha256','launcherSha256','verifierSha256','aclHelperSha256','releaseSigningHelperSha256','packageCustodians')){$expected[$name]=$record[$name]}
Assert-InstallerApprovalRecord ([pscustomobject]$record) $expected
$destination=[IO.Path]::GetFullPath($OutputPath);$parent=[IO.Path]::GetDirectoryName($destination)
if(-not(Test-Path -LiteralPath $parent -PathType Container)){throw 'Approval record destination directory does not exist'}
$stream=[IO.File]::Open($destination,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
try{$writer=[IO.StreamWriter]::new($stream,[Text.UTF8Encoding]::new($false));try{$writer.Write(($record|ConvertTo-Json -Depth 4)+"`n")}finally{$writer.Dispose()}}finally{if($stream){$stream.Dispose()}}
$hash=(Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Output "Installer approval record created: $destination"
Write-Output "Independently record this approval SHA-256: $hash"
