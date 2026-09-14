param(
  [Parameter(Mandatory=$true)][string]$InstallRoot,
  [Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$')][string]$ReleaseId,
  [Parameter(Mandatory=$true)][string]$ServiceAccount,
  [Parameter(Mandatory=$true)][string[]]$ApprovedAdministrators,
  [string]$TaskName='Performance-Tracker-Application',
  [string]$HealthUrl='http://127.0.0.1:3100/api/health',
  [Parameter(Mandatory=$true)][string]$MigrationEvidencePath,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ApprovedMigrationEvidenceSha256,
  [Parameter(Mandatory=$true)][string]$ReceiptPath,
  [Parameter(Mandatory=$true)][string]$ReceiptSigningPrivateKey,
  [Parameter(Mandatory=$true)][string]$ReceiptSigningPublicKey,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$TrustedReceiptPublicKeySha256,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$TrustedReleasePublicKeySha256,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$TrustedNodeRuntimeSha256
)
$ErrorActionPreference='Stop'
function Get-Sha256([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Write-NewJson([string]$Path,$Value){$stream=[IO.File]::Open($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read);try{$bytes=[Text.UTF8Encoding]::new($false).GetBytes(($Value|ConvertTo-Json -Depth 7));$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}}
$principal=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if(-not$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Production receipt requires an elevated deployment administrator'}
if($TaskName-ne'Performance-Tracker-Application'){throw 'Production application task name is fixed'}
if([string]::IsNullOrWhiteSpace($env:RELEASE_SIGNING_KEY_PASSPHRASE)-or$env:RELEASE_SIGNING_KEY_PASSPHRASE.Length-lt20){throw 'RELEASE_SIGNING_KEY_PASSPHRASE is required for receipt signing'}
$root=[IO.Path]::GetFullPath($InstallRoot).TrimEnd('\');$release=[IO.Path]::GetFullPath((Join-Path $root "releases\$ReleaseId")).TrimEnd('\')
if(-not$release.StartsWith("$root\releases\",[StringComparison]::OrdinalIgnoreCase)){throw 'Release path escaped the installation root'}
$evidence=[IO.Path]::GetFullPath($MigrationEvidencePath);$receipt=[IO.Path]::GetFullPath($ReceiptPath);$receiptSignature="$receipt.sig.json"
$privateKey=[IO.Path]::GetFullPath($ReceiptSigningPrivateKey);$publicKey=[IO.Path]::GetFullPath($ReceiptSigningPublicKey)
foreach($path in @($evidence,$privateKey,$publicKey)){if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Receipt input was not found: $path"}}
if($privateKey.StartsWith("$root\",[StringComparison]::OrdinalIgnoreCase)){throw 'Receipt private key must remain outside the installation root'}
if((Get-Sha256 $publicKey)-ne$TrustedReceiptPublicKeySha256.ToLowerInvariant()){throw 'Receipt public key fingerprint does not match independent approval'}
if((Get-Sha256 $evidence)-ne$ApprovedMigrationEvidenceSha256.ToLowerInvariant()){throw 'Migration evidence fingerprint does not match independent approval'}
$migration=Get-Content -LiteralPath $evidence -Raw|ConvertFrom-Json
$migrationFields=@('format','status','releaseId','completedAt','applicationRole','migrations','databaseUrlsRecorded')
if((@($migration.PSObject.Properties.Name|Sort-Object)-join',')-ne(@($migrationFields|Sort-Object)-join',')-or$migration.format-ne'performance-tracker-migration-evidence-v1'-or$migration.status-ne'PASS'-or$migration.releaseId-ne$ReleaseId-or$migration.databaseUrlsRecorded-ne$false){throw 'Migration evidence is invalid or belongs to another release'}
$releaseKey=Join-Path $root 'config\release-signing-public.pem';$node=Join-Path $root 'runtime\node.exe';$manifest=Join-Path $release '.next\standalone\release-manifest.json';$manifestSignature=Join-Path $release '.next\standalone\release-manifest.sig.json'
foreach($path in @($releaseKey,$node,$manifest,$manifestSignature)){if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Installed trust artifact is missing: $path"}}
if((Get-Sha256 $releaseKey)-ne$TrustedReleasePublicKeySha256.ToLowerInvariant()){throw 'Installed release trust key fingerprint changed'}
if((Get-Sha256 $node)-ne$TrustedNodeRuntimeSha256.ToLowerInvariant()){throw 'Installed Node.js runtime fingerprint changed'}
$signingHelper=Join-Path $release 'scripts\release-signing.mjs';$integrityHelper=Join-Path $release 'scripts\release-integrity.mjs'
& $node $signingHelper verify $manifest $manifestSignature $releaseKey;if($LASTEXITCODE-ne0){throw 'Installed release signature verification failed'}
& $node $integrityHelper verify (Join-Path $release '.next\standalone') (Join-Path $release 'scripts');if($LASTEXITCODE-ne0){throw 'Installed release integrity verification failed'}
$manifestRecord=Get-Content -LiteralPath $manifest -Raw|ConvertFrom-Json
if($manifestRecord.commit-notmatch'^[0-9a-f]{40}$'){throw 'Installed release manifest commit is invalid'}
$task=Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop;$taskInfo=Get-ScheduledTaskInfo -TaskName $TaskName -ErrorAction Stop
$taskBinding=(@($task.Actions)|ForEach-Object{"$($_.WorkingDirectory) $($_.Arguments)"})-join' '
if($taskBinding.IndexOf($release,[StringComparison]::OrdinalIgnoreCase)-lt0){throw 'Production application task is not bound to the installed release'}
$expectedServiceSid=([Security.Principal.NTAccount]::new($ServiceAccount)).Translate([Security.Principal.SecurityIdentifier]).Value
$taskSid=([Security.Principal.NTAccount]::new([string]$task.Principal.UserId)).Translate([Security.Principal.SecurityIdentifier]).Value
if($taskSid-ne$expectedServiceSid){throw 'Production application task uses the wrong service account'}
if($task.State-ne'Running'-or$taskInfo.LastTaskResult-notin@(0,267009)){throw 'Production application task is not healthy'}
$health=[Uri]$HealthUrl;if($health.Scheme-ne'http'-or$health.Host-notin@('127.0.0.1','localhost','::1')){throw 'HealthUrl must use loopback HTTP'}
$response=Invoke-WebRequest -UseBasicParsing -Uri $health.AbsoluteUri -TimeoutSec 10
if($response.StatusCode-ne200){throw 'Production health endpoint did not return HTTP 200'}
$healthBody=$response.Content|ConvertFrom-Json;if($healthBody.ok-ne$true){throw 'Production health contract did not report ok'}
$aclJson=& (Join-Path $release 'scripts\verify-production-acls.ps1') -ReleaseDirectory $release -ConfigDirectory (Join-Path $root 'config') -EvidenceDirectory (Join-Path $root 'evidence') -QuarantineDirectory (Join-Path $root 'quarantine') -LogDirectory (Join-Path $root 'logs') -ServiceAccount $ServiceAccount -ApprovedAdministrators $ApprovedAdministrators|Out-String
if($LASTEXITCODE-ne0){throw 'Final production ACL verification failed'}
$acl=$aclJson|ConvertFrom-Json;if($acl.status-ne'PASS'){throw 'Final production ACL verification did not pass'}
$record=[ordered]@{format='performance-tracker-production-installation-receipt-v1';status='PASS';completedAt=[DateTimeOffset]::UtcNow.ToString('o');host=[Environment]::MachineName;operatorSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;releaseId=$ReleaseId;releaseCommit=[string]$manifestRecord.commit;releaseManifestSha256=Get-Sha256 $manifest;migrationEvidenceSha256=$ApprovedMigrationEvidenceSha256.ToLowerInvariant();applicationTaskName=$TaskName;applicationTaskState=[string]$task.State;serviceAccountSid=$expectedServiceSid;healthStatus='ok';healthEndpoint='loopback';aclVerificationSha256=([BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash([Text.UTF8Encoding]::new($false).GetBytes($aclJson)))).Replace('-','').ToLowerInvariant();receiptPublicKeySha256=$TrustedReceiptPublicKeySha256.ToLowerInvariant();containsSecrets=$false}
Write-NewJson $receipt $record
try{& $node $signingHelper sign $receipt $privateKey $receiptSignature;if($LASTEXITCODE-ne0){throw 'Production receipt signing failed'};& $node $signingHelper verify $receipt $receiptSignature $publicKey;if($LASTEXITCODE-ne0){throw 'Production receipt verification failed'}}catch{Remove-Item -LiteralPath $receipt,$receiptSignature -Force -ErrorAction SilentlyContinue;throw}
Write-Output "Signed production installation receipt: $receipt"
Write-Output "Production receipt SHA-256: $(Get-Sha256 $receipt)"
