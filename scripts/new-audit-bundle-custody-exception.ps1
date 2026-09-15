param(
  [Parameter(Mandatory=$true)][string]$HandoffPath,
  [Parameter(Mandatory=$true)][string]$HandoffSignaturePath,
  [Parameter(Mandatory=$true)][string]$SenderPublicKey,
  [Parameter(Mandatory=$true)][string]$ExpectedReceiptPath,
  [Parameter(Mandatory=$true)][string]$NodeExecutable,
  [Parameter(Mandatory=$true)][string]$ReleaseSigningHelper,
  [Parameter(Mandatory=$true)][string]$ExceptionSigningPrivateKey,
  [Parameter(Mandatory=$true)][string]$ExceptionSigningPublicKey,
  [Parameter(Mandatory=$true)][string]$ExceptionPath,
  [Parameter(Mandatory=$true)][ValidateSet('ACKNOWLEDGEMENT_OVERDUE','RECEIVER_UNAVAILABLE','TRANSFER_MEDIA_LOST','TRANSFER_CANCELLED')][string]$Reason,
  [Parameter(Mandatory=$true)][ValidateRange(1,720)][int]$AcknowledgementHours,
  [Parameter(Mandatory=$true)][ValidatePattern('^S-1-(?:\d+-)*\d+$')][string[]]$AuthorizedCustodianSids,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ApprovedHandoffSha256,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ApprovedSenderPublicKeySha256,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ApprovedNodeExecutableSha256,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ApprovedReleaseSigningHelperSha256,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ExpectedManifestSha256,
  [Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$')][string]$ExpectedReleaseId,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{40}$')][string]$ExpectedReleaseCommit,
  [Parameter(Mandatory=$true)][string]$ExpectedHost
)
$ErrorActionPreference='Stop'
function Get-Sha256([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Assert-OrdinaryPath([string]$Path){$current=Get-Item -LiteralPath $Path -Force -ErrorAction Stop;while($current){if(($current.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw "Custody exception path contains a reparse point: $($current.FullName)"};$parent=[IO.Path]::GetDirectoryName($current.FullName);if([string]::IsNullOrWhiteSpace($parent)-or$parent-eq$current.FullName){break};$current=Get-Item -LiteralPath $parent -Force -ErrorAction Stop}}
function Write-NewJson([string]$Path,$Value){$stream=[IO.File]::Open($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read);try{$bytes=[Text.UTF8Encoding]::new($false).GetBytes(($Value|ConvertTo-Json -Depth 5));$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}}
if([string]::IsNullOrWhiteSpace($env:RELEASE_SIGNING_KEY_PASSPHRASE)-or$env:RELEASE_SIGNING_KEY_PASSPHRASE.Length-lt20){throw 'RELEASE_SIGNING_KEY_PASSPHRASE is required for custody exception signing'}
$handoff=[IO.Path]::GetFullPath($HandoffPath);$handoffSignature=[IO.Path]::GetFullPath($HandoffSignaturePath);$senderKey=[IO.Path]::GetFullPath($SenderPublicKey);$receipt=[IO.Path]::GetFullPath($ExpectedReceiptPath);$receiptSignature="$receipt.sig.json";$node=[IO.Path]::GetFullPath($NodeExecutable);$helper=[IO.Path]::GetFullPath($ReleaseSigningHelper);$privateKey=[IO.Path]::GetFullPath($ExceptionSigningPrivateKey);$publicKey=[IO.Path]::GetFullPath($ExceptionSigningPublicKey);$exception=[IO.Path]::GetFullPath($ExceptionPath);$exceptionSignature="$exception.sig.json"
foreach($path in @($handoff,$handoffSignature,$senderKey,$node,$helper,$privateKey,$publicKey)){if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Custody exception input not found: $path"};Assert-OrdinaryPath $path}
foreach($path in @($receipt,$receiptSignature,$exception,$exceptionSignature)){if(Test-Path -LiteralPath $path){throw 'A custody receipt or exception already exists'}}
$receiptParent=Split-Path $receipt -Parent;$exceptionParent=Split-Path $exception -Parent
foreach($parent in @($receiptParent,$exceptionParent)){if(-not(Test-Path -LiteralPath $parent -PathType Container)){throw "Custody evidence parent not found: $parent"};Assert-OrdinaryPath $parent}
$custodians=@($AuthorizedCustodianSids|Sort-Object -Unique);if($custodians.Count-ne$AuthorizedCustodianSids.Count){throw 'Authorized custodian SIDs must be unique'}
$currentSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
if($currentSid-notin$custodians){throw 'Current Windows identity is not an approved custody exception signer'}
$streams=[Collections.Generic.List[IO.FileStream]]::new()
try{
  foreach($path in @($handoff,$handoffSignature,$senderKey,$node,$helper,$privateKey,$publicKey)){$streams.Add([IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read))}
  foreach($pair in @(@($handoff,$ApprovedHandoffSha256),@($senderKey,$ApprovedSenderPublicKeySha256),@($node,$ApprovedNodeExecutableSha256),@($helper,$ApprovedReleaseSigningHelperSha256))){if((Get-Sha256 $pair[0])-ne$pair[1].ToLowerInvariant()){throw 'Custody exception input fingerprint does not match independent approval'}}
  $nodeSignature=Get-AuthenticodeSignature -LiteralPath $node
  if($nodeSignature.Status-ne'Valid'-or$nodeSignature.SignerCertificate.Subject-notmatch'(^|,\s*)O=OpenJS Foundation(,|$)'){throw 'Custody exception requires an authentic OpenJS Foundation Node.js runtime'}
  & $node $helper verify $handoff $handoffSignature $senderKey;if($LASTEXITCODE-ne0){throw 'Custody handoff signature verification failed'}
  try{$record=Get-Content -LiteralPath $handoff -Raw|ConvertFrom-Json}catch{throw 'Custody handoff is not valid JSON'}
  $required=@('format','status','transferId','handedOffAt','senderSid','receiverSid','transferMethod','manifestSha256','bundlePublicKeySha256','releaseId','releaseCommit','host','custodyPublicKeySha256','containsSecrets')
  if((@($record.PSObject.Properties.Name|Sort-Object)-join',')-ne(@($required|Sort-Object)-join',')){throw 'Custody handoff schema is incomplete or contains unknown fields'}
  if($record.format-ne'performance-tracker-audit-custody-handoff-v1'-or$record.status-ne'HANDED_OFF'-or$record.containsSecrets-ne$false-or$record.custodyPublicKeySha256-ne$ApprovedSenderPublicKeySha256.ToLowerInvariant()){throw 'Custody handoff is not an approved redacted record'}
  if($record.manifestSha256-ne$ExpectedManifestSha256.ToLowerInvariant()-or$record.releaseId-ne$ExpectedReleaseId-or$record.releaseCommit-ne$ExpectedReleaseCommit.ToLowerInvariant()-or$record.host-ne$ExpectedHost){throw 'Custody handoff belongs to another deployment'}
  try{$handedOffAt=[DateTimeOffset]::ParseExact([string]$record.handedOffAt,'o',[Globalization.CultureInfo]::InvariantCulture)}catch{throw 'Custody handoff timestamp must use round-trip UTC format'}
  if($handedOffAt.Offset-ne[TimeSpan]::Zero-or$handedOffAt-gt[DateTimeOffset]::UtcNow.AddMinutes(5)){throw 'Custody handoff timestamp is invalid'}
  $dueAt=$handedOffAt.AddHours($AcknowledgementHours);$now=[DateTimeOffset]::UtcNow
  if($Reason-eq'ACKNOWLEDGEMENT_OVERDUE'-and$now-lt$dueAt){throw 'Custody acknowledgement window has not expired'}
  foreach($path in @($receipt,$receiptSignature)){if(Test-Path -LiteralPath $path){throw 'A receiver custody receipt already exists'}}
  $exceptionRecord=[ordered]@{format='performance-tracker-audit-custody-exception-v1';status='EXCEPTION';transferId=$record.transferId;exceptionAt=$now.ToString('o');handedOffAt=$record.handedOffAt;acknowledgementHours=$AcknowledgementHours;dueAt=$dueAt.ToString('o');reason=$Reason;authorizedCustodianSid=$currentSid;senderSid=$record.senderSid;receiverSid=$record.receiverSid;transferMethod=$record.transferMethod;handoffSha256=$ApprovedHandoffSha256.ToLowerInvariant();manifestSha256=$ExpectedManifestSha256.ToLowerInvariant();releaseId=$ExpectedReleaseId;releaseCommit=$ExpectedReleaseCommit.ToLowerInvariant();host=$ExpectedHost;exceptionPublicKeySha256=Get-Sha256 $publicKey;receiptPresent=$false;containsSecrets=$false}
  try{Write-NewJson $exception $exceptionRecord;& $node $helper sign $exception $privateKey $exceptionSignature;if($LASTEXITCODE-ne0){throw 'Custody exception signing failed'};& $node $helper verify $exception $exceptionSignature $publicKey;if($LASTEXITCODE-ne0){throw 'Custody exception signature verification failed'};foreach($path in @($receipt,$receiptSignature)){if(Test-Path -LiteralPath $path){throw 'A receiver custody receipt appeared during exception creation'}}}catch{Remove-Item -LiteralPath $exception,$exceptionSignature -Force -ErrorAction SilentlyContinue;throw}
}finally{for($index=$streams.Count-1;$index-ge0;$index--){$streams[$index].Dispose()}}
Write-Output "Signed audit custody exception: $exception"
Write-Output "Custody exception SHA-256: $(Get-Sha256 $exception)"

