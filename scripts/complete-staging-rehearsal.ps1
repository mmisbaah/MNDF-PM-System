param(
  [Parameter(Mandatory=$true)][string]$ExpectedMachineName,
  [Parameter(Mandatory=$true)][string]$RehearsalRoot,
  [Parameter(Mandatory=$true)][string]$CurrentLink,
  [Parameter(Mandatory=$true)][string]$EvidenceDirectory,
  [Parameter(Mandatory=$true)][string]$SealDirectory,
  [Parameter(Mandatory=$true)][string]$RehearsalTaskName,
  [Parameter(Mandatory=$true)][string]$EvidenceSigningPrivateKey,
  [Parameter(Mandatory=$true)][string]$EvidenceSigningPublicKey,
  [Parameter(Mandatory=$true)][string]$NodeExecutable,
  [switch]$ConfirmDisposableHostCleanup
)
$ErrorActionPreference='Stop'
function Get-Sha256([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Assert-OrdinaryTree([string]$Root,[string]$AllowedJunction=''){
  foreach($item in @(Get-Item -LiteralPath $Root -Force)+@(Get-ChildItem -LiteralPath $Root -Force -Recurse)){
    if(($item.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0-and$item.FullName-ne$AllowedJunction){throw "Cleanup path contains an unapproved junction or symbolic link: $($item.FullName)"}
  }
}
function Get-EvidenceInventory([string]$Root){
  @((Get-ChildItem -LiteralPath $Root -File -Force -Recurse|Sort-Object FullName|ForEach-Object{
    [ordered]@{path=$_.FullName.Substring($Root.Length+1).Replace('\','/');sha256=Get-Sha256 $_.FullName}
  }))
}
function Write-NewJson([string]$Path,$Value){
  $stream=[IO.File]::Open($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
  try{$bytes=[Text.UTF8Encoding]::new($false).GetBytes(($Value|ConvertTo-Json -Depth 8));$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
}
if(-not$ConfirmDisposableHostCleanup){throw 'Use -ConfirmDisposableHostCleanup only for an approved disposable-host cleanup'}
if($ExpectedMachineName-ne[Environment]::MachineName){throw 'ExpectedMachineName does not match the current host'}
$principal=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if(-not$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Staging cleanup requires an elevated deployment-administrator session'}
if([string]::IsNullOrWhiteSpace($env:RELEASE_SIGNING_KEY_PASSPHRASE)-or$env:RELEASE_SIGNING_KEY_PASSPHRASE.Length-lt20){throw 'RELEASE_SIGNING_KEY_PASSPHRASE is required for the evidence signing key'}
$root=[IO.Path]::GetFullPath($RehearsalRoot).TrimEnd('\')
$current=[IO.Path]::GetFullPath($CurrentLink).TrimEnd('\')
$evidence=[IO.Path]::GetFullPath($EvidenceDirectory).TrimEnd('\')
$seal=[IO.Path]::GetFullPath($SealDirectory).TrimEnd('\')
$productionRoot=[IO.Path]::GetFullPath("$env:SystemDrive\PerformanceTracker").TrimEnd('\')
$systemRoot=[IO.Path]::GetFullPath("$env:SystemDrive\").TrimEnd('\')
if($root-eq$systemRoot-or$root-eq$productionRoot-or$root.StartsWith("$productionRoot\",[StringComparison]::OrdinalIgnoreCase)){throw 'Refusing to clean a system or production path'}
if((Split-Path $root -Leaf)-notmatch'^PerformanceTracker-rehearsal-[A-Za-z0-9._-]+$'){throw 'RehearsalRoot leaf must use the guarded PerformanceTracker-rehearsal- prefix'}
if($current-ne(Join-Path $root 'current')){throw 'CurrentLink must be the guarded current junction directly inside RehearsalRoot'}
if($evidence-eq$root-or$evidence.StartsWith("$root\",[StringComparison]::OrdinalIgnoreCase)){throw 'EvidenceDirectory must be outside RehearsalRoot'}
if($seal-eq$root-or$seal.StartsWith("$root\",[StringComparison]::OrdinalIgnoreCase)-or$seal-eq$evidence-or$seal.StartsWith("$evidence\",[StringComparison]::OrdinalIgnoreCase)){throw 'SealDirectory must be separate from rehearsal and evidence directories'}
if(-not(Test-Path -LiteralPath $root -PathType Container)){throw 'RehearsalRoot was not found'}
if(-not(Test-Path -LiteralPath $evidence -PathType Container)){throw 'EvidenceDirectory was not found'}
if(Test-Path -LiteralPath $seal){throw 'SealDirectory must not already exist'}
if($RehearsalTaskName-notmatch'^Performance-Tracker-Rehearsal-[A-Za-z0-9._-]+$'){throw 'Only an explicitly named rehearsal task may be removed'}
$privateKey=[IO.Path]::GetFullPath($EvidenceSigningPrivateKey);$publicKey=[IO.Path]::GetFullPath($EvidenceSigningPublicKey);$node=[IO.Path]::GetFullPath($NodeExecutable)
foreach($path in @($privateKey,$publicKey,$node)){if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Evidence trust input was not found: $path"}}
foreach($path in @($privateKey,$publicKey,$node)){if($path.StartsWith("$root\",[StringComparison]::OrdinalIgnoreCase)){throw 'Evidence trust inputs must be outside RehearsalRoot'}}
$currentItem=Get-Item -LiteralPath $current -Force
if($currentItem.LinkType-ne'Junction'){throw 'CurrentLink must be an existing junction'}
$currentTarget=[IO.Path]::GetFullPath([string]$currentItem.Target).TrimEnd('\');$releaseRoot=Join-Path $root 'releases'
if(-not$currentTarget.StartsWith("$releaseRoot\",[StringComparison]::OrdinalIgnoreCase)){throw 'CurrentLink target must remain inside the rehearsal releases directory'}
Assert-OrdinaryTree $root $current;Assert-OrdinaryTree $evidence
$files=@(Get-ChildItem -LiteralPath $evidence -File -Force -Recurse)
foreach($pattern in @('staging-host-readiness-.*\.json$','promotion-rollback-rehearsal-.*\.json$','deployment-operations\.jsonl$','application-.*\.log$')){
  if(-not@($files|Where-Object{$_.Name-match$pattern}).Count){throw "Required rehearsal evidence is missing: $pattern"}
}
$planFiles=@($files|Where-Object{$_.Name-match'promotion-rehearsal-plan.*\.json$'})
if($planFiles.Count-ne1){throw 'Exactly one promotion rehearsal plan must be retained as evidence'}
$resultFile=@($files|Where-Object{$_.Name-match'promotion-rollback-rehearsal-.*\.json$'})|Select-Object -Last 1
$result=Get-Content -LiteralPath $resultFile.FullName -Raw|ConvertFrom-Json
if($result.status-ne'PASS'){throw 'Promotion and rollback evidence has not passed'}
New-Item -ItemType Directory -Path $seal|Out-Null
$signingHelper=Join-Path $PSScriptRoot 'release-signing.mjs'
$preManifest=Join-Path $seal 'pre-cleanup-evidence-manifest.json';$preSignature=Join-Path $seal 'pre-cleanup-evidence-manifest.sig.json'
$pre=[ordered]@{format='performance-tracker-rehearsal-evidence-pre-cleanup-v1';host=[Environment]::MachineName;sealedAt=(Get-Date).ToUniversalTime().ToString('o');rehearsalRoot=$root;evidenceDirectory=$evidence;publicKeySha256=Get-Sha256 $publicKey;files=Get-EvidenceInventory $evidence}
Write-NewJson $preManifest $pre
& $node $signingHelper sign $preManifest $privateKey $preSignature
if($LASTEXITCODE-ne0){throw 'Pre-cleanup evidence signing failed'}
& $node $signingHelper verify $preManifest $preSignature $publicKey
if($LASTEXITCODE-ne0){throw 'Pre-cleanup evidence verification failed'}

$cleanupStatus='STARTED';$cleanupFailure=$null
try {
  $task=Get-ScheduledTask -TaskName $RehearsalTaskName -ErrorAction Stop
  $binding=(@($task.Actions)|ForEach-Object{"$($_.WorkingDirectory) $($_.Arguments)"})-join' '
  if($binding.IndexOf($root,[StringComparison]::OrdinalIgnoreCase)-lt0){throw 'Rehearsal task is not bound to the approved rehearsal root'}
  Stop-ScheduledTask -TaskName $RehearsalTaskName -ErrorAction SilentlyContinue
  Unregister-ScheduledTask -TaskName $RehearsalTaskName -Confirm:$false
  if(Get-ScheduledTask -TaskName $RehearsalTaskName -ErrorAction SilentlyContinue){throw 'Rehearsal scheduled task still exists after removal'}
  $junction=Get-Item -LiteralPath $current -Force
  if($junction.LinkType-ne'Junction'){throw 'CurrentLink changed before cleanup'}
  Remove-Item -LiteralPath $current -Force
  Assert-OrdinaryTree $root
  Remove-Item -LiteralPath $root -Recurse -Force
  if(Test-Path -LiteralPath $root){throw 'Rehearsal root still exists after cleanup'}
  $cleanupStatus='PASS'
} catch {$cleanupStatus='FAIL';$cleanupFailure=$_.Exception.Message;throw}
finally {
  $cleanup=[ordered]@{format='performance-tracker-staging-cleanup-v1';status=$cleanupStatus;completedAt=(Get-Date).ToUniversalTime().ToString('o');host=[Environment]::MachineName;operatorSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;rehearsalRoot=$root;currentLink=$current;taskName=$RehearsalTaskName;failure=$cleanupFailure}
  Write-NewJson (Join-Path $seal 'cleanup-result.json') $cleanup
}
$finalManifest=Join-Path $seal 'final-evidence-manifest.json';$finalSignature=Join-Path $seal 'final-evidence-manifest.sig.json'
$sealInputs=@(Get-EvidenceInventory $evidence)+@(Get-ChildItem -LiteralPath $seal -File|Where-Object{$_.Name-notmatch'^final-evidence-manifest'}|Sort-Object Name|ForEach-Object{[ordered]@{path="seal/$($_.Name)";sha256=Get-Sha256 $_.FullName}})
$final=[ordered]@{format='performance-tracker-rehearsal-evidence-final-v1';status='PASS';host=[Environment]::MachineName;sealedAt=(Get-Date).ToUniversalTime().ToString('o');publicKeySha256=Get-Sha256 $publicKey;files=$sealInputs}
Write-NewJson $finalManifest $final
& $node $signingHelper sign $finalManifest $privateKey $finalSignature
if($LASTEXITCODE-ne0){throw 'Final evidence signing failed'}
& $node $signingHelper verify $finalManifest $finalSignature $publicKey
if($LASTEXITCODE-ne0){throw 'Final evidence verification failed'}
Write-Output "Staging rehearsal cleanup passed. Final evidence seal: $finalManifest"
Write-Output "Final evidence manifest SHA-256: $(Get-Sha256 $finalManifest)"
