param(
  [Parameter(Mandatory=$true)][string]$BundleDirectory,
  [Parameter(Mandatory=$true)][string]$BundleVerifier,
  [Parameter(Mandatory=$true)][string]$NodeExecutable,
  [Parameter(Mandatory=$true)][string]$ReleaseSigningHelper,
  [Parameter(Mandatory=$true)][string]$CustodySigningPrivateKey,
  [Parameter(Mandatory=$true)][string]$CustodySigningPublicKey,
  [Parameter(Mandatory=$true)][ValidatePattern('^S-1-(?:\d+-)*\d+$')][string]$ReceiverSid,
  [Parameter(Mandatory=$true)][ValidateSet('OFFLINE_ENCRYPTED_MEDIA','SECURE_MANAGED_SHARE','PHYSICAL_CUSTODY')][string]$TransferMethod,
  [Parameter(Mandatory=$true)][string]$HandoffPath,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ApprovedBundleVerifierSha256,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ApprovedManifestSha256,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ApprovedBundlePublicKeySha256,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ApprovedNodeExecutableSha256,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ApprovedReleaseSigningHelperSha256,
  [Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$')][string]$ExpectedReleaseId,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{40}$')][string]$ExpectedReleaseCommit,
  [Parameter(Mandatory=$true)][string]$ExpectedHost
)
$ErrorActionPreference='Stop'
function Get-Sha256([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Write-NewJson([string]$Path,$Value){$stream=[IO.File]::Open($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read);try{$bytes=[Text.UTF8Encoding]::new($false).GetBytes(($Value|ConvertTo-Json -Depth 6));$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}}
if([string]::IsNullOrWhiteSpace($env:RELEASE_SIGNING_KEY_PASSPHRASE)-or$env:RELEASE_SIGNING_KEY_PASSPHRASE.Length-lt20){throw 'RELEASE_SIGNING_KEY_PASSPHRASE is required for custody signing'}
$handoff=[IO.Path]::GetFullPath($HandoffPath);$signature="$handoff.sig.json";$privateKey=[IO.Path]::GetFullPath($CustodySigningPrivateKey);$publicKey=[IO.Path]::GetFullPath($CustodySigningPublicKey);$node=[IO.Path]::GetFullPath($NodeExecutable);$helper=[IO.Path]::GetFullPath($ReleaseSigningHelper);$verifier=[IO.Path]::GetFullPath($BundleVerifier)
foreach($path in @($privateKey,$publicKey,$node,$helper,$verifier)){if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Custody input not found: $path"}}
if(Test-Path -LiteralPath $handoff -or Test-Path -LiteralPath $signature){throw 'Custody handoff and signature must not already exist'}
$senderSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
if($senderSid-eq$ReceiverSid){throw 'Sender and receiver must be different Windows identities'}
& $verifier -BundleDirectory $BundleDirectory -NodeExecutable $node -ExternalReleaseSigningHelper $helper -ApprovedVerifierSha256 $ApprovedBundleVerifierSha256 -ApprovedManifestSha256 $ApprovedManifestSha256 -ApprovedBundlePublicKeySha256 $ApprovedBundlePublicKeySha256 -ApprovedNodeExecutableSha256 $ApprovedNodeExecutableSha256 -ApprovedExternalSigningHelperSha256 $ApprovedReleaseSigningHelperSha256 -ExpectedReleaseId $ExpectedReleaseId -ExpectedReleaseCommit $ExpectedReleaseCommit -ExpectedHost $ExpectedHost
if($LASTEXITCODE-ne0){throw 'Audit bundle verification failed before custody handoff'}
$record=[ordered]@{format='performance-tracker-audit-custody-handoff-v1';status='HANDED_OFF';transferId=[Guid]::NewGuid().ToString('D');handedOffAt=[DateTimeOffset]::UtcNow.ToString('o');senderSid=$senderSid;receiverSid=$ReceiverSid;transferMethod=$TransferMethod;manifestSha256=$ApprovedManifestSha256.ToLowerInvariant();bundlePublicKeySha256=$ApprovedBundlePublicKeySha256.ToLowerInvariant();releaseId=$ExpectedReleaseId;releaseCommit=$ExpectedReleaseCommit.ToLowerInvariant();host=$ExpectedHost;custodyPublicKeySha256=Get-Sha256 $publicKey;containsSecrets=$false}
try{Write-NewJson $handoff $record;& $node $helper sign $handoff $privateKey $signature;if($LASTEXITCODE-ne0){throw 'Custody handoff signing failed'};& $node $helper verify $handoff $signature $publicKey;if($LASTEXITCODE-ne0){throw 'Custody handoff signature verification failed'}}catch{Remove-Item -LiteralPath $handoff,$signature -Force -ErrorAction SilentlyContinue;throw}
Write-Output "Signed audit custody handoff: $handoff"
Write-Output "Custody handoff SHA-256: $(Get-Sha256 $handoff)"

