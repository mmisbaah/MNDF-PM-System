param(
  [Parameter(Mandatory=$true)][string]$FinalEvidenceManifest,
  [Parameter(Mandatory=$true)][string]$FinalEvidenceSignature,
  [Parameter(Mandatory=$true)][string]$EvidencePublicKey,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ApprovedEvidenceManifestSha256,
  [Parameter(Mandatory=$true)][string]$InstallerApprovalPath,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ApprovedInstallerApprovalSha256,
  [Parameter(Mandatory=$true)][ValidatePattern('^S-1-(?:\d+-)*\d+$')][string]$RehearsalOperatorSid,
  [Parameter(Mandatory=$true)][ValidatePattern('^S-1-(?:\d+-)*\d+$')][string]$AuthorizerSid,
  [Parameter(Mandatory=$true)][ValidateSet('GO','NO_GO')][string]$Decision,
  [Parameter(Mandatory=$true)][ValidateLength(10,1000)][string]$DecisionReason,
  [Parameter(Mandatory=$true)][string]$Confirmation,
  [Parameter(Mandatory=$true)][string]$OutputPath,
  [Parameter(Mandatory=$true)][string]$AcceptanceSigningPrivateKey,
  [Parameter(Mandatory=$true)][string]$AcceptanceSigningPublicKey,
  [Parameter(Mandatory=$true)][string]$NodeExecutable
)
$ErrorActionPreference='Stop'
function Get-Sha256([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Read-Json([string]$Path,[string]$Label){
  if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw "$Label was not found"}
  try{return Get-Content -LiteralPath $Path -Raw|ConvertFrom-Json}catch{throw "$Label is not valid JSON"}
}
function Assert-ExactSchema($Value,[string[]]$Fields,[string]$Label){
  if((@($Value.PSObject.Properties.Name|Sort-Object)-join',')-ne(@($Fields|Sort-Object)-join',')){throw "$Label schema is incomplete or contains unknown fields"}
}
function Write-NewJson([string]$Path,$Value){
  $stream=[IO.File]::Open($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
  try{$bytes=[Text.UTF8Encoding]::new($false).GetBytes(($Value|ConvertTo-Json -Depth 8));$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
}
if([string]::IsNullOrWhiteSpace($env:RELEASE_SIGNING_KEY_PASSPHRASE)-or$env:RELEASE_SIGNING_KEY_PASSPHRASE.Length-lt20){throw 'RELEASE_SIGNING_KEY_PASSPHRASE is required for the acceptance signing key'}
$manifestPath=[IO.Path]::GetFullPath($FinalEvidenceManifest);$signaturePath=[IO.Path]::GetFullPath($FinalEvidenceSignature)
$evidenceKey=[IO.Path]::GetFullPath($EvidencePublicKey);$approvalPath=[IO.Path]::GetFullPath($InstallerApprovalPath)
$privateKey=[IO.Path]::GetFullPath($AcceptanceSigningPrivateKey);$publicKey=[IO.Path]::GetFullPath($AcceptanceSigningPublicKey);$node=[IO.Path]::GetFullPath($NodeExecutable)
foreach($path in @($manifestPath,$signaturePath,$evidenceKey,$approvalPath,$privateKey,$publicKey,$node)){if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Acceptance input was not found: $path"}}
$output=[IO.Path]::GetFullPath($OutputPath);$outputParent=[IO.Path]::GetDirectoryName($output)
if(-not(Test-Path -LiteralPath $outputParent -PathType Container)){throw 'Acceptance destination directory does not exist'}
if(Test-Path -LiteralPath $output){throw 'Acceptance record already exists'}
$outputSignature="$output.sig.json"
if(Test-Path -LiteralPath $outputSignature){throw 'Acceptance signature already exists'}
if((Get-Sha256 $manifestPath)-ne$ApprovedEvidenceManifestSha256.ToLowerInvariant()){throw 'Final evidence manifest fingerprint does not match independent approval'}
if((Get-Sha256 $approvalPath)-ne$ApprovedInstallerApprovalSha256.ToLowerInvariant()){throw 'Installer approval fingerprint does not match independent approval'}
$signingHelper=Join-Path $PSScriptRoot 'release-signing.mjs'
& $node $signingHelper verify $manifestPath $signaturePath $evidenceKey
if($LASTEXITCODE-ne0){throw 'Final evidence manifest signature verification failed'}
$manifest=Read-Json $manifestPath 'Final evidence manifest'
Assert-ExactSchema $manifest @('format','status','host','sealedAt','publicKeySha256','files') 'Final evidence manifest'
if($manifest.format-ne'performance-tracker-rehearsal-evidence-final-v1'-or$manifest.status-ne'PASS'){throw 'Final evidence manifest is not a passed rehearsal seal'}
if($manifest.host-ne[Environment]::MachineName){throw 'Final evidence manifest belongs to a different host'}
if($manifest.publicKeySha256-ne(Get-Sha256 $evidenceKey)){throw 'Evidence public key does not match the sealed fingerprint'}
$cleanupEntry=@($manifest.files|Where-Object{$_.path-eq'seal/cleanup-result.json'})
if($cleanupEntry.Count-ne1-or$cleanupEntry[0].sha256-notmatch'^[0-9a-f]{64}$'){throw 'Final evidence manifest does not uniquely bind cleanup evidence'}
$cleanupPath=Join-Path ([IO.Path]::GetDirectoryName($manifestPath)) 'cleanup-result.json'
$cleanup=Read-Json $cleanupPath 'Cleanup result'
if((Get-Sha256 $cleanupPath)-ne$cleanupEntry[0].sha256){throw 'Cleanup result changed after evidence sealing'}
Assert-ExactSchema $cleanup @('format','status','completedAt','host','operatorSid','rehearsalRoot','currentLink','taskName','failure') 'Cleanup result'
if($cleanup.format-ne'performance-tracker-staging-cleanup-v1'-or$cleanup.status-ne'PASS'-or$cleanup.host-ne$manifest.host){throw 'Cleanup evidence is not a passed result for this host'}
if($cleanup.operatorSid.ToUpperInvariant()-ne$RehearsalOperatorSid.ToUpperInvariant()){throw 'Rehearsal operator SID does not match cleanup evidence'}
if($AuthorizerSid.ToUpperInvariant()-eq$RehearsalOperatorSid.ToUpperInvariant()){throw 'The rehearsal operator and release authorizer must be different accounts'}
$currentSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
if($currentSid.ToUpperInvariant()-ne$AuthorizerSid.ToUpperInvariant()){throw 'The signed-in Windows account must match AuthorizerSid'}
$approval=Read-Json $approvalPath 'Installer approval record'
if($approval.format-ne'performance-tracker-install-approval-v1'){throw 'Unsupported installer approval record'}
$now=[DateTimeOffset]::UtcNow
if([DateTimeOffset]::Parse([string]$approval.expiresAtUtc)-le$now){throw 'Installer approval has expired'}
if($approval.releaseCommit-notmatch'^[0-9a-f]{40}$'-or$approval.installerSha256-notmatch'^[0-9a-f]{64}$'-or[string]::IsNullOrWhiteSpace([string]$approval.releaseId)){throw 'Installer approval release identity is incomplete'}
$expectedConfirmation=if($Decision-eq'GO'){"AUTHORIZE GO $($approval.releaseId)"}else{"AUTHORIZE NO_GO $($approval.releaseId)"}
if($Confirmation-ne$expectedConfirmation){throw "Confirmation must exactly match: $expectedConfirmation"}
$record=[ordered]@{
  format='performance-tracker-rehearsal-acceptance-v1';decision=$Decision;decisionReason=$DecisionReason.Trim()
  authorizedAt=$now.ToString('o');host=$manifest.host;authorizerSid=$AuthorizerSid.ToUpperInvariant();rehearsalOperatorSid=$RehearsalOperatorSid.ToUpperInvariant()
  releaseId=[string]$approval.releaseId;releaseCommit=[string]$approval.releaseCommit;installerSha256=[string]$approval.installerSha256
  installerApprovalSha256=$ApprovedInstallerApprovalSha256.ToLowerInvariant();finalEvidenceManifestSha256=$ApprovedEvidenceManifestSha256.ToLowerInvariant()
  evidencePublicKeySha256=Get-Sha256 $evidenceKey;acceptancePublicKeySha256=Get-Sha256 $publicKey
}
Write-NewJson $output $record
try{
  & $node $signingHelper sign $output $privateKey $outputSignature
  if($LASTEXITCODE-ne0){throw 'Acceptance record signing failed'}
  & $node $signingHelper verify $output $outputSignature $publicKey
  if($LASTEXITCODE-ne0){throw 'Acceptance record verification failed'}
}catch{
  Remove-Item -LiteralPath $output -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $outputSignature -Force -ErrorAction SilentlyContinue
  throw
}
Write-Output "Rehearsal acceptance decision: $Decision"
Write-Output "Signed acceptance record: $output"
Write-Output "Independently record this acceptance SHA-256: $(Get-Sha256 $output)"
