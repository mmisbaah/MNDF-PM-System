param(
  [Parameter(Mandatory=$true)][string]$ReceiptPath,
  [Parameter(Mandatory=$true)][string]$ReceiptSignaturePath,
  [Parameter(Mandatory=$true)][string]$ReceiptPublicKey,
  [Parameter(Mandatory=$true)][string]$NodeExecutable,
  [Parameter(Mandatory=$true)][string]$ReleaseSigningHelper,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ApprovedReceiptSha256,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ApprovedReceiptPublicKeySha256,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ApprovedNodeExecutableSha256,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ApprovedReleaseSigningHelperSha256,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ApprovedVerifierSha256,
  [Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$')][string]$ExpectedReleaseId,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{40}$')][string]$ExpectedReleaseCommit,
  [Parameter(Mandatory=$true)][string]$ExpectedHost
)
$ErrorActionPreference='Stop'
function Get-Sha256([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Assert-OrdinaryPath([string]$Path){
  $current=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
  while($current){
    if(($current.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw "Receipt verification path contains a reparse point: $($current.FullName)"}
    $parent=[IO.Path]::GetDirectoryName($current.FullName);if([string]::IsNullOrWhiteSpace($parent)-or$parent-eq$current.FullName){break};$current=Get-Item -LiteralPath $parent -Force -ErrorAction Stop
  }
}
$verifier=[IO.Path]::GetFullPath($MyInvocation.MyCommand.Path);$receipt=[IO.Path]::GetFullPath($ReceiptPath);$signature=[IO.Path]::GetFullPath($ReceiptSignaturePath);$publicKey=[IO.Path]::GetFullPath($ReceiptPublicKey);$node=[IO.Path]::GetFullPath($NodeExecutable);$helper=[IO.Path]::GetFullPath($ReleaseSigningHelper)
$inputs=@($verifier,$receipt,$signature,$publicKey,$node,$helper);$streams=[Collections.Generic.List[IO.FileStream]]::new()
try{
  foreach($path in $inputs){if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Receipt verification input was not found: $path"};Assert-OrdinaryPath $path;$streams.Add([IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read))}
  if((Get-Sha256 $verifier)-ne$ApprovedVerifierSha256.ToLowerInvariant()){throw 'Receipt verifier fingerprint does not match independent approval'}
  if((Get-Sha256 $receipt)-ne$ApprovedReceiptSha256.ToLowerInvariant()){throw 'Production receipt fingerprint does not match independent approval'}
  if((Get-Sha256 $publicKey)-ne$ApprovedReceiptPublicKeySha256.ToLowerInvariant()){throw 'Receipt public-key fingerprint does not match independent approval'}
  if((Get-Sha256 $node)-ne$ApprovedNodeExecutableSha256.ToLowerInvariant()){throw 'Node.js verifier fingerprint does not match independent approval'}
  if((Get-Sha256 $helper)-ne$ApprovedReleaseSigningHelperSha256.ToLowerInvariant()){throw 'Receipt verification helper fingerprint does not match independent approval'}
  $nodeSignature=Get-AuthenticodeSignature -LiteralPath $node
  if($nodeSignature.Status-ne'Valid'-or$nodeSignature.SignerCertificate.Subject-notmatch'(^|,\s*)O=OpenJS Foundation(,|$)'){throw 'Receipt verification requires an authentic OpenJS Foundation Node.js runtime'}
  & $node $helper verify $receipt $signature $publicKey
  if($LASTEXITCODE-ne0){throw 'Production installation receipt signature verification failed'}
  try{$record=Get-Content -LiteralPath $receipt -Raw|ConvertFrom-Json}catch{throw 'Production installation receipt is not valid JSON'}
  $required=@('format','status','completedAt','host','operatorSid','releaseId','releaseCommit','releaseManifestSha256','migrationEvidenceSha256','applicationTaskName','applicationTaskState','serviceAccountSid','healthStatus','healthEndpoint','aclVerificationSha256','receiptPublicKeySha256','containsSecrets')
  if((@($record.PSObject.Properties.Name|Sort-Object)-join',')-ne(@($required|Sort-Object)-join',')){throw 'Production installation receipt schema is incomplete or contains unknown fields'}
  if($record.format-ne'performance-tracker-production-installation-receipt-v1'-or$record.status-ne'PASS'-or$record.containsSecrets-ne$false){throw 'Production installation receipt is not a passed, redacted record'}
  if($record.releaseId-ne$ExpectedReleaseId-or$record.releaseCommit-ne$ExpectedReleaseCommit.ToLowerInvariant()-or$record.host-ne$ExpectedHost){throw 'Production installation receipt belongs to another deployment'}
  if($record.receiptPublicKeySha256-ne$ApprovedReceiptPublicKeySha256.ToLowerInvariant()){throw 'Production installation receipt is bound to another public key'}
  foreach($name in @('releaseManifestSha256','migrationEvidenceSha256','aclVerificationSha256','receiptPublicKeySha256')){if(([string]$record.$name)-notmatch'^[0-9a-f]{64}$'){throw "Production installation receipt has an invalid $name"}}
  foreach($name in @('operatorSid','serviceAccountSid')){if(([string]$record.$name)-notmatch'^S-1-(?:\d+-)*\d+$'){throw "Production installation receipt has an invalid $name"}}
  try{$completed=[DateTimeOffset]::ParseExact([string]$record.completedAt,'o',[Globalization.CultureInfo]::InvariantCulture)}catch{throw 'Production installation receipt timestamp must use round-trip UTC format'}
  if($completed.Offset-ne[TimeSpan]::Zero-or$completed-gt[DateTimeOffset]::UtcNow.AddMinutes(5)){throw 'Production installation receipt timestamp is future-dated'}
  if($record.applicationTaskName-ne'Performance-Tracker-Application'-or$record.applicationTaskState-ne'Running'-or$record.healthStatus-ne'ok'-or$record.healthEndpoint-ne'loopback'){throw 'Production installation receipt does not record a healthy local application'}
}finally{for($index=$streams.Count-1;$index-ge0;$index--){$streams[$index].Dispose()}}
Write-Output "Production installation receipt verified: $ApprovedReceiptSha256"
Write-Output "Release: $ExpectedReleaseId ($($ExpectedReleaseCommit.ToLowerInvariant()))"
