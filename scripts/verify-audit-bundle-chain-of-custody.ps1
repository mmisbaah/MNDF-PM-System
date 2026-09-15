param(
  [Parameter(Mandatory=$true)][string]$HandoffPath,
  [Parameter(Mandatory=$true)][string]$HandoffSignaturePath,
  [Parameter(Mandatory=$true)][string]$SenderPublicKey,
  [Parameter(Mandatory=$true)][string]$ReceiptPath,
  [Parameter(Mandatory=$true)][string]$ReceiptSignaturePath,
  [Parameter(Mandatory=$true)][string]$ReceiverPublicKey,
  [Parameter(Mandatory=$true)][string]$NodeExecutable,
  [Parameter(Mandatory=$true)][string]$ReleaseSigningHelper,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ApprovedVerifierSha256,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ApprovedHandoffSha256,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ApprovedReceiptSha256,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ApprovedSenderPublicKeySha256,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ApprovedReceiverPublicKeySha256,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ApprovedNodeExecutableSha256,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ApprovedReleaseSigningHelperSha256,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ExpectedManifestSha256,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ExpectedBundlePublicKeySha256,
  [Parameter(Mandatory=$true)][ValidatePattern('^S-1-(?:\d+-)*\d+$')][string]$ExpectedSenderSid,
  [Parameter(Mandatory=$true)][ValidatePattern('^S-1-(?:\d+-)*\d+$')][string]$ExpectedReceiverSid,
  [Parameter(Mandatory=$true)][ValidateSet('OFFLINE_ENCRYPTED_MEDIA','SECURE_MANAGED_SHARE','PHYSICAL_CUSTODY')][string]$ExpectedTransferMethod,
  [Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$')][string]$ExpectedReleaseId,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{40}$')][string]$ExpectedReleaseCommit,
  [Parameter(Mandatory=$true)][string]$ExpectedHost
)
$ErrorActionPreference='Stop'
function Get-Sha256([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Assert-OrdinaryPath([string]$Path){$current=Get-Item -LiteralPath $Path -Force -ErrorAction Stop;while($current){if(($current.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw "Custody verification path contains a reparse point: $($current.FullName)"};$parent=[IO.Path]::GetDirectoryName($current.FullName);if([string]::IsNullOrWhiteSpace($parent)-or$parent-eq$current.FullName){break};$current=Get-Item -LiteralPath $parent -Force -ErrorAction Stop}}
function Assert-ExactSchema($Record,[string[]]$Fields,[string]$Label){$actual=@($Record.PSObject.Properties.Name|Sort-Object)-join',';$expected=@($Fields|Sort-Object)-join',';if($actual-ne$expected){throw "$Label schema is incomplete or contains unknown fields"}}
function Read-UtcTimestamp([string]$Value,[string]$Label){try{$parsed=[DateTimeOffset]::ParseExact($Value,'o',[Globalization.CultureInfo]::InvariantCulture)}catch{throw "$Label must use round-trip UTC format"};if($parsed.Offset-ne[TimeSpan]::Zero-or$parsed-gt[DateTimeOffset]::UtcNow.AddMinutes(5)){throw "$Label is not a valid UTC time"};$parsed}
$verifier=[IO.Path]::GetFullPath($MyInvocation.MyCommand.Path);$handoff=[IO.Path]::GetFullPath($HandoffPath);$handoffSignature=[IO.Path]::GetFullPath($HandoffSignaturePath);$senderKey=[IO.Path]::GetFullPath($SenderPublicKey);$receipt=[IO.Path]::GetFullPath($ReceiptPath);$receiptSignature=[IO.Path]::GetFullPath($ReceiptSignaturePath);$receiverKey=[IO.Path]::GetFullPath($ReceiverPublicKey);$node=[IO.Path]::GetFullPath($NodeExecutable);$helper=[IO.Path]::GetFullPath($ReleaseSigningHelper)
$inputs=@($verifier,$handoff,$handoffSignature,$senderKey,$receipt,$receiptSignature,$receiverKey,$node,$helper);$streams=[Collections.Generic.List[IO.FileStream]]::new()
try{
  foreach($path in $inputs){if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Custody verification input not found: $path"};Assert-OrdinaryPath $path;$streams.Add([IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read))}
  $approved=@{$verifier=$ApprovedVerifierSha256;$handoff=$ApprovedHandoffSha256;$receipt=$ApprovedReceiptSha256;$senderKey=$ApprovedSenderPublicKeySha256;$receiverKey=$ApprovedReceiverPublicKeySha256;$node=$ApprovedNodeExecutableSha256;$helper=$ApprovedReleaseSigningHelperSha256}
  foreach($name in $approved.Keys){$path=Get-Variable -Name $name -ValueOnly;if((Get-Sha256 $path)-ne$approved[$name].ToLowerInvariant()){throw "Approved $name fingerprint does not match custody evidence"}}
  $nodeSignature=Get-AuthenticodeSignature -LiteralPath $node
  if($nodeSignature.Status-ne'Valid'-or$nodeSignature.SignerCertificate.Subject-notmatch'(^|,\s*)O=OpenJS Foundation(,|$)'){throw 'Custody verification requires an authentic OpenJS Foundation Node.js runtime'}
  & $node $helper verify $handoff $handoffSignature $senderKey;if($LASTEXITCODE-ne0){throw 'Sender custody signature verification failed'}
  & $node $helper verify $receipt $receiptSignature $receiverKey;if($LASTEXITCODE-ne0){throw 'Receiver custody signature verification failed'}
  try{$handoffRecord=Get-Content -LiteralPath $handoff -Raw|ConvertFrom-Json;$receiptRecord=Get-Content -LiteralPath $receipt -Raw|ConvertFrom-Json}catch{throw 'Custody evidence is not valid JSON'}
  Assert-ExactSchema $handoffRecord @('format','status','transferId','handedOffAt','senderSid','receiverSid','transferMethod','manifestSha256','bundlePublicKeySha256','releaseId','releaseCommit','host','custodyPublicKeySha256','containsSecrets') 'Custody handoff'
  Assert-ExactSchema $receiptRecord @('format','status','transferId','receivedAt','senderSid','receiverSid','transferMethod','handoffSha256','manifestSha256','bundleVerified','releaseId','releaseCommit','host','receiverPublicKeySha256','containsSecrets') 'Custody receipt'
  if($handoffRecord.format-ne'performance-tracker-audit-custody-handoff-v1'-or$handoffRecord.status-ne'HANDED_OFF'-or$handoffRecord.containsSecrets-ne$false){throw 'Custody handoff is not a valid redacted record'}
  if($receiptRecord.format-ne'performance-tracker-audit-custody-receipt-v1'-or$receiptRecord.status-ne'RECEIVED'-or$receiptRecord.containsSecrets-ne$false-or$receiptRecord.bundleVerified-ne$true){throw 'Custody receipt is not a verified, redacted record'}
  $handedOffAt=Read-UtcTimestamp ([string]$handoffRecord.handedOffAt) 'Handoff timestamp';$receivedAt=Read-UtcTimestamp ([string]$receiptRecord.receivedAt) 'Receipt timestamp'
  if($receivedAt-lt$handedOffAt){throw 'Custody receipt predates its handoff'}
  if(([string]$handoffRecord.transferId)-notmatch'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'){throw 'Custody transfer identifier is not a version 4 UUID'}
  if($handoffRecord.transferId-ne$receiptRecord.transferId-or$handoffRecord.senderSid-ne$receiptRecord.senderSid-or$handoffRecord.receiverSid-ne$receiptRecord.receiverSid-or$handoffRecord.transferMethod-ne$receiptRecord.transferMethod){throw 'Custody receipt does not match its handoff'}
  if($handoffRecord.senderSid-ne$ExpectedSenderSid-or$handoffRecord.receiverSid-ne$ExpectedReceiverSid-or$handoffRecord.senderSid-eq$handoffRecord.receiverSid-or$handoffRecord.transferMethod-ne$ExpectedTransferMethod){throw 'Custody identities or transfer method do not match independent approval'}
  if($handoffRecord.manifestSha256-ne$ExpectedManifestSha256.ToLowerInvariant()-or$receiptRecord.manifestSha256-ne$ExpectedManifestSha256.ToLowerInvariant()-or$handoffRecord.bundlePublicKeySha256-ne$ExpectedBundlePublicKeySha256.ToLowerInvariant()){throw 'Custody records reference an unapproved audit bundle'}
  if($receiptRecord.handoffSha256-ne$ApprovedHandoffSha256.ToLowerInvariant()-or$handoffRecord.custodyPublicKeySha256-ne$ApprovedSenderPublicKeySha256.ToLowerInvariant()-or$receiptRecord.receiverPublicKeySha256-ne$ApprovedReceiverPublicKeySha256.ToLowerInvariant()){throw 'Custody records are not bound to the approved handoff and keys'}
  foreach($record in @($handoffRecord,$receiptRecord)){if($record.releaseId-ne$ExpectedReleaseId-or$record.releaseCommit-ne$ExpectedReleaseCommit.ToLowerInvariant()-or$record.host-ne$ExpectedHost){throw 'Custody evidence belongs to another deployment'}}
}finally{for($index=$streams.Count-1;$index-ge0;$index--){$streams[$index].Dispose()}}
Write-Output "Audit bundle chain of custody verified: $($handoffRecord.transferId)"
Write-Output "Handoff: $($ApprovedHandoffSha256.ToLowerInvariant())"
Write-Output "Receipt: $($ApprovedReceiptSha256.ToLowerInvariant())"

