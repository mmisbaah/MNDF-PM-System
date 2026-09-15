param(
  [Parameter(Mandatory=$true)][string]$ArchiveManifestPath,[Parameter(Mandatory=$true)][string]$ArchiveManifestSignaturePath,[Parameter(Mandatory=$true)][string]$ArchivePublicKey,
  [Parameter(Mandatory=$true)][string]$NodeExecutable,[Parameter(Mandatory=$true)][string]$ReleaseSigningHelper,
  [Parameter(Mandatory=$true)][string]$RetentionSigningPrivateKey,[Parameter(Mandatory=$true)][string]$RetentionSigningPublicKey,[Parameter(Mandatory=$true)][string]$PolicyPath,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ApprovedArchiveManifestSha256,[Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ApprovedArchivePublicKeySha256,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ApprovedNodeExecutableSha256,[Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ApprovedReleaseSigningHelperSha256,
  [Parameter(Mandatory=$true)][ValidatePattern('^S-1-(?:\d+-)*\d+$')][string]$CustodianSid,
  [Parameter(Mandatory=$true)][ValidateRange(1,366)][int]$ReviewIntervalDays,[Parameter(Mandatory=$true)][ValidateRange(1,25)][int]$RetentionYears,
  [Parameter(Mandatory=$true)][ValidateSet('REVIEW_REQUIRED','AUTHORIZED_DESTRUCTION','PERMANENT_RETENTION')][string]$AfterRetentionAction,
  [Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$')][string]$ExpectedReleaseId,[Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{40}$')][string]$ExpectedReleaseCommit,[Parameter(Mandatory=$true)][string]$ExpectedHost
)
$ErrorActionPreference='Stop'
function Get-Sha256([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Assert-OrdinaryPath([string]$Path){$current=Get-Item -LiteralPath $Path -Force -ErrorAction Stop;while($current){if(($current.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw "Retention-policy path contains a reparse point: $($current.FullName)"};$parent=[IO.Path]::GetDirectoryName($current.FullName);if([string]::IsNullOrWhiteSpace($parent)-or$parent-eq$current.FullName){break};$current=Get-Item -LiteralPath $parent -Force -ErrorAction Stop}}
function Assert-ExactSchema($Record,[string[]]$Fields,[string]$Label){if((@($Record.PSObject.Properties.Name|Sort-Object)-join',')-ne(@($Fields|Sort-Object)-join',')){throw "$Label schema is incomplete or contains unknown fields"}}
function Write-NewJson([string]$Path,$Value){$stream=[IO.File]::Open($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read);try{$bytes=[Text.UTF8Encoding]::new($false).GetBytes(($Value|ConvertTo-Json -Depth 5));$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}}
if([string]::IsNullOrWhiteSpace($env:RELEASE_SIGNING_KEY_PASSPHRASE)-or$env:RELEASE_SIGNING_KEY_PASSPHRASE.Length-lt20){throw 'RELEASE_SIGNING_KEY_PASSPHRASE is required for retention-policy signing'}
$manifest=[IO.Path]::GetFullPath($ArchiveManifestPath);$manifestSignature=[IO.Path]::GetFullPath($ArchiveManifestSignaturePath);$archiveKey=[IO.Path]::GetFullPath($ArchivePublicKey);$node=[IO.Path]::GetFullPath($NodeExecutable);$helper=[IO.Path]::GetFullPath($ReleaseSigningHelper);$privateKey=[IO.Path]::GetFullPath($RetentionSigningPrivateKey);$publicKey=[IO.Path]::GetFullPath($RetentionSigningPublicKey);$policy=[IO.Path]::GetFullPath($PolicyPath);$policySignature="$policy.sig.json"
$inputs=@($manifest,$manifestSignature,$archiveKey,$node,$helper,$privateKey,$publicKey);foreach($path in $inputs){if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Retention-policy input not found: $path"};Assert-OrdinaryPath $path}
if((Test-Path -LiteralPath $policy)-or(Test-Path -LiteralPath $policySignature)){throw 'Retention policy and signature must not already exist'}
if($privateKey-eq$policy-or$privateKey-eq$policySignature){throw 'Retention private key must remain separate from policy evidence'}
$streams=[Collections.Generic.List[IO.FileStream]]::new()
try{
  foreach($path in $inputs){$streams.Add([IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read))}
  foreach($pair in @(@($manifest,$ApprovedArchiveManifestSha256),@($archiveKey,$ApprovedArchivePublicKeySha256),@($node,$ApprovedNodeExecutableSha256),@($helper,$ApprovedReleaseSigningHelperSha256))){if((Get-Sha256 $pair[0])-ne$pair[1].ToLowerInvariant()){throw 'Retention-policy trust input fingerprint does not match independent approval'}}
  $nodeSignature=Get-AuthenticodeSignature -LiteralPath $node;if($nodeSignature.Status-ne'Valid'-or$nodeSignature.SignerCertificate.Subject-notmatch'(^|,\s*)O=OpenJS Foundation(,|$)'){throw 'Retention policy requires an authentic OpenJS Foundation Node.js runtime'}
  & $node $helper verify $manifest $manifestSignature $archiveKey;if($LASTEXITCODE-ne0){throw 'Final archive manifest signature verification failed before retention approval'}
  try{$archive=Get-Content -LiteralPath $manifest -Raw|ConvertFrom-Json}catch{throw 'Final archive manifest is not valid JSON'}
  Assert-ExactSchema $archive @('format','status','createdAt','releaseId','releaseCommit','host','custodyOutcomeType','closureSha256','closurePublicKeySha256','runtime','files','containsSecrets') 'Final archive manifest'
  if($archive.format-ne'performance-tracker-final-deployment-archive-v1'-or$archive.status-ne'SEALED'-or$archive.containsSecrets-ne$false){throw 'Retention policy requires a sealed, redacted final archive'}
  if($archive.releaseId-ne$ExpectedReleaseId-or$archive.releaseCommit-ne$ExpectedReleaseCommit.ToLowerInvariant()-or$archive.host-ne$ExpectedHost){throw 'Final archive belongs to another deployment'}
  $now=[DateTimeOffset]::UtcNow;$record=[ordered]@{format='performance-tracker-final-archive-retention-policy-v1';status='ACTIVE';approvedAt=$now.ToString('o');approvedBySid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;custodianSid=$CustodianSid;releaseId=$ExpectedReleaseId;releaseCommit=$ExpectedReleaseCommit.ToLowerInvariant();host=$ExpectedHost;archiveManifestSha256=$ApprovedArchiveManifestSha256.ToLowerInvariant();archivePublicKeySha256=$ApprovedArchivePublicKeySha256.ToLowerInvariant();nextReviewAt=$now.AddDays($ReviewIntervalDays).ToString('o');retainUntil=$now.AddYears($RetentionYears).ToString('o');reviewIntervalDays=$ReviewIntervalDays;retentionYears=$RetentionYears;afterRetentionAction=$AfterRetentionAction;automaticDeletion=$false;retentionPublicKeySha256=Get-Sha256 $publicKey;containsSecrets=$false}
  try{Write-NewJson $policy $record;& $node $helper sign $policy $privateKey $policySignature;if($LASTEXITCODE-ne0){throw 'Retention-policy signing failed'};& $node $helper verify $policy $policySignature $publicKey;if($LASTEXITCODE-ne0){throw 'Retention-policy signature verification failed'}}catch{Remove-Item -LiteralPath $policy,$policySignature -Force -ErrorAction SilentlyContinue;throw}
}finally{for($index=$streams.Count-1;$index-ge0;$index--){$streams[$index].Dispose()}}
Write-Output "Signed final archive retention policy: $policy"
Write-Output "Retention policy SHA-256: $(Get-Sha256 $policy)"
Write-Output "Retention public-key SHA-256: $(Get-Sha256 $publicKey)"
