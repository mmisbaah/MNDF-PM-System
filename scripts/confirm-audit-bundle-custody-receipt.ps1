param(
  [Parameter(Mandatory=$true)][string]$HandoffPath,[Parameter(Mandatory=$true)][string]$HandoffSignaturePath,[Parameter(Mandatory=$true)][string]$SenderCustodyPublicKey,
  [Parameter(Mandatory=$true)][string]$BundleDirectory,[Parameter(Mandatory=$true)][string]$BundleVerifier,[Parameter(Mandatory=$true)][string]$NodeExecutable,[Parameter(Mandatory=$true)][string]$ReleaseSigningHelper,
  [Parameter(Mandatory=$true)][string]$ReceiverSigningPrivateKey,[Parameter(Mandatory=$true)][string]$ReceiverSigningPublicKey,[Parameter(Mandatory=$true)][string]$ReceiptPath,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ApprovedHandoffSha256,[Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ApprovedSenderPublicKeySha256,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ApprovedBundleVerifierSha256,[Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ApprovedManifestSha256,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ApprovedBundlePublicKeySha256,[Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ApprovedNodeExecutableSha256,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ApprovedReleaseSigningHelperSha256,[Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$')][string]$ExpectedReleaseId,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{40}$')][string]$ExpectedReleaseCommit,[Parameter(Mandatory=$true)][string]$ExpectedHost
)
$ErrorActionPreference='Stop'
function Get-Sha256([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Write-NewJson([string]$Path,$Value){$stream=[IO.File]::Open($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read);try{$bytes=[Text.UTF8Encoding]::new($false).GetBytes(($Value|ConvertTo-Json -Depth 5));$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}}
if([string]::IsNullOrWhiteSpace($env:RELEASE_SIGNING_KEY_PASSPHRASE)-or$env:RELEASE_SIGNING_KEY_PASSPHRASE.Length-lt20){throw 'RELEASE_SIGNING_KEY_PASSPHRASE is required for custody receipt signing'}
$handoff=[IO.Path]::GetFullPath($HandoffPath);$handoffSignature=[IO.Path]::GetFullPath($HandoffSignaturePath);$senderKey=[IO.Path]::GetFullPath($SenderCustodyPublicKey);$receipt=[IO.Path]::GetFullPath($ReceiptPath);$receiptSignature="$receipt.sig.json";$receiverPrivateKey=[IO.Path]::GetFullPath($ReceiverSigningPrivateKey);$receiverPublicKey=[IO.Path]::GetFullPath($ReceiverSigningPublicKey);$node=[IO.Path]::GetFullPath($NodeExecutable);$helper=[IO.Path]::GetFullPath($ReleaseSigningHelper);$verifier=[IO.Path]::GetFullPath($BundleVerifier)
foreach($path in @($handoff,$handoffSignature,$senderKey,$receiverPrivateKey,$receiverPublicKey,$node,$helper,$verifier)){if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Custody receipt input not found: $path"}}
if(Test-Path -LiteralPath $receipt -or Test-Path -LiteralPath $receiptSignature){throw 'Custody receipt and signature must not already exist'}
if((Get-Sha256 $handoff)-ne$ApprovedHandoffSha256.ToLowerInvariant()){throw 'Custody handoff fingerprint does not match independent approval'}
if((Get-Sha256 $senderKey)-ne$ApprovedSenderPublicKeySha256.ToLowerInvariant()){throw 'Sender custody key fingerprint does not match independent approval'}
& $node $helper verify $handoff $handoffSignature $senderKey;if($LASTEXITCODE-ne0){throw 'Custody handoff signature verification failed'}
try{$record=Get-Content -LiteralPath $handoff -Raw|ConvertFrom-Json}catch{throw 'Custody handoff is not valid JSON'}
$required=@('format','status','transferId','handedOffAt','senderSid','receiverSid','transferMethod','manifestSha256','bundlePublicKeySha256','releaseId','releaseCommit','host','custodyPublicKeySha256','containsSecrets')
if((@($record.PSObject.Properties.Name|Sort-Object)-join',')-ne(@($required|Sort-Object)-join',')){throw 'Custody handoff schema is incomplete or contains unknown fields'}
if($record.format-ne'performance-tracker-audit-custody-handoff-v1'-or$record.status-ne'HANDED_OFF'-or$record.containsSecrets-ne$false){throw 'Custody handoff is not a valid redacted handoff'}
$receiverSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
if($record.receiverSid-ne$receiverSid){throw 'Only the named receiver Windows identity may confirm custody'}
if($record.manifestSha256-ne$ApprovedManifestSha256.ToLowerInvariant()-or$record.bundlePublicKeySha256-ne$ApprovedBundlePublicKeySha256.ToLowerInvariant()-or$record.releaseId-ne$ExpectedReleaseId-or$record.releaseCommit-ne$ExpectedReleaseCommit.ToLowerInvariant()-or$record.host-ne$ExpectedHost-or$record.custodyPublicKeySha256-ne$ApprovedSenderPublicKeySha256.ToLowerInvariant()){throw 'Custody handoff does not match the approved deployment'}
& $verifier -BundleDirectory $BundleDirectory -NodeExecutable $node -ExternalReleaseSigningHelper $helper -ApprovedVerifierSha256 $ApprovedBundleVerifierSha256 -ApprovedManifestSha256 $ApprovedManifestSha256 -ApprovedBundlePublicKeySha256 $ApprovedBundlePublicKeySha256 -ApprovedNodeExecutableSha256 $ApprovedNodeExecutableSha256 -ApprovedExternalSigningHelperSha256 $ApprovedReleaseSigningHelperSha256 -ExpectedReleaseId $ExpectedReleaseId -ExpectedReleaseCommit $ExpectedReleaseCommit -ExpectedHost $ExpectedHost
if($LASTEXITCODE-ne0){throw 'Audit bundle verification failed before custody receipt'}
$confirmation=[ordered]@{format='performance-tracker-audit-custody-receipt-v1';status='RECEIVED';transferId=$record.transferId;receivedAt=[DateTimeOffset]::UtcNow.ToString('o');senderSid=$record.senderSid;receiverSid=$receiverSid;transferMethod=$record.transferMethod;handoffSha256=$ApprovedHandoffSha256.ToLowerInvariant();manifestSha256=$ApprovedManifestSha256.ToLowerInvariant();bundleVerified=$true;releaseId=$ExpectedReleaseId;releaseCommit=$ExpectedReleaseCommit.ToLowerInvariant();host=$ExpectedHost;receiverPublicKeySha256=Get-Sha256 $receiverPublicKey;containsSecrets=$false}
try{Write-NewJson $receipt $confirmation;& $node $helper sign $receipt $receiverPrivateKey $receiptSignature;if($LASTEXITCODE-ne0){throw 'Custody receipt signing failed'};& $node $helper verify $receipt $receiptSignature $receiverPublicKey;if($LASTEXITCODE-ne0){throw 'Custody receipt signature verification failed'}}catch{Remove-Item -LiteralPath $receipt,$receiptSignature -Force -ErrorAction SilentlyContinue;throw}
Write-Output "Signed audit custody receipt: $receipt"
Write-Output "Custody receipt SHA-256: $(Get-Sha256 $receipt)"

