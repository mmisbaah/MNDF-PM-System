param(
  [Parameter(Mandatory=$true)][string]$InstallerPath,
  [Parameter(Mandatory=$true)][string]$BuildRecordPath,
  [Parameter(Mandatory=$true)][string]$ReleasePublicKey,
  [Parameter(Mandatory=$true)][string]$RehearsalRoot,
  [string]$EvidenceDirectory,
  [switch]$ConfirmDisposableHost
)
$ErrorActionPreference='Stop'

function Get-Sha256([string]$Path){
  (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
function Assert-OrdinaryDirectory([string]$Path){
  $item=Get-Item -LiteralPath $Path -Force
  if(($item.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw "Rehearsal path cannot be a junction or symbolic link: $Path"}
}

if(-not$ConfirmDisposableHost){throw 'Use -ConfirmDisposableHost only on an approved disposable Windows staging host'}
$principal=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if(-not$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Installer rehearsal requires an elevated deployment-administrator session'}

$installer=[IO.Path]::GetFullPath($InstallerPath)
$recordPath=[IO.Path]::GetFullPath($BuildRecordPath)
$publicKey=[IO.Path]::GetFullPath($ReleasePublicKey)
$root=[IO.Path]::GetFullPath($RehearsalRoot).TrimEnd('\')
$systemDriveRoot=[IO.Path]::GetFullPath("$env:SystemDrive\").TrimEnd('\')
$productionRoot=[IO.Path]::GetFullPath("$env:SystemDrive\PerformanceTracker").TrimEnd('\')
if($root-eq$systemDriveRoot-or$root-eq$productionRoot-or$root.StartsWith("$productionRoot\",[StringComparison]::OrdinalIgnoreCase)){
  throw 'RehearsalRoot must not be the production installation path or a system-drive root'
}
if(Test-Path -LiteralPath $root){throw 'RehearsalRoot must not already exist'}
foreach($path in @($installer,$recordPath,$publicKey)){
  if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Required rehearsal input was not found: $path"}
}

$record=Get-Content -LiteralPath $recordPath -Raw|ConvertFrom-Json
if($record.format-ne'performance-tracker-installer-build-v9'-or$record.productionAuthorized-ne$false-or$record.authenticodeStatus-ne'NotSigned'){
  throw 'This runner accepts only an explicitly unsigned, non-production rehearsal build record'
}
if($record.installerFile-ne[IO.Path]::GetFileName($installer)){throw 'Build record does not name the selected installer'}
if((Get-Sha256 $installer)-ne$record.sha256){throw 'Installer fingerprint does not match its build record'}
if((Get-Sha256 $publicKey)-ne$record.releasePublicKeySha256){throw 'Release public-key fingerprint does not match the build record'}

$evidence=if($EvidenceDirectory){[IO.Path]::GetFullPath($EvidenceDirectory)}else{Join-Path ([IO.Path]::GetDirectoryName($root)) 'PerformanceTracker-rehearsal-evidence'}
New-Item -ItemType Directory -Path $evidence -Force|Out-Null
Assert-OrdinaryDirectory $evidence
$operationId=[guid]::NewGuid().ToString('N')
$started=(Get-Date).ToUniversalTime()
$logPath=Join-Path $evidence "installer-$operationId.log"
$resultPath=Join-Path $evidence "installer-rehearsal-$operationId.json"
$result=[ordered]@{
  format='performance-tracker-installer-rehearsal-v1';operationId=$operationId;status='STARTED'
  startedAt=$started.ToString('o');completedAt=$null;host=[Environment]::MachineName
  operatorSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
  installerSha256=$record.sha256;releaseCommit=$record.releaseCommit;releaseId=$record.releaseId;version=$record.version
  rehearsalRoot=$root;phases=[Collections.Generic.List[object]]::new();retainedPaths=@();failure=$null
}
function Add-Phase([string]$Name,[string]$Status,[string]$Detail){
  $result.phases.Add([ordered]@{name=$Name;status=$Status;at=(Get-Date).ToUniversalTime().ToString('o');detail=$Detail})
}
function Save-Result(){
  [IO.File]::WriteAllText($resultPath,($result|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
}

try {
  Save-Result
  $arguments=@('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/SP-',('/DIR="{0}"'-f$root),('/LOG="{0}"'-f$logPath))
  $process=Start-Process -FilePath $installer -ArgumentList $arguments -Wait -PassThru
  if($process.ExitCode-ne0){throw "Installer exited with code $($process.ExitCode)"}
  Add-Phase 'install' 'PASS' 'Unsigned rehearsal installer completed on the disposable host.'

  if(-not(Test-Path -LiteralPath $root -PathType Container)){throw 'Installer did not create the rehearsal root'}
  Assert-OrdinaryDirectory $root
  $release=Join-Path $root "releases\$($record.releaseId)"
  $node=Join-Path $root 'runtime\node.exe'
  $installedKey=Join-Path $root 'config\release-signing-public.pem'
  $server=Join-Path $release '.next\standalone\server.js'
  foreach($path in @($release,$node,$installedKey,$server)){
    if(-not(Test-Path -LiteralPath $path)){throw "Installed payload is incomplete: $path"}
  }
  if((Get-Sha256 $node)-ne$record.nodeRuntimeSha256){throw 'Installed Node.js runtime fingerprint changed'}
  if((Get-Sha256 $installedKey)-ne$record.releasePublicKeySha256){throw 'Installed release public key fingerprint changed'}
  $manifest=Join-Path $release '.next\standalone\release-manifest.json'
  $signature=Join-Path (Split-Path $manifest -Parent) 'release-manifest.sig.json'
  & $node (Join-Path $release 'scripts\release-signing.mjs') verify $manifest $signature $installedKey
  if($LASTEXITCODE-ne0){throw 'Installed release signature verification failed'}
  & $node (Join-Path $release 'scripts\release-integrity.mjs') verify (Join-Path $release '.next\standalone') (Join-Path $release 'scripts')
  if($LASTEXITCODE-ne0){throw 'Installed package integrity verification failed'}
  Add-Phase 'installed-integrity' 'PASS' 'Runtime, trust key, signed manifest, and complete installed payload passed verification.'

  $retentionSentinels=@(
    (Join-Path $root 'config\rehearsal-retention.txt'),
    (Join-Path $root 'evidence\rehearsal-retention.txt'),
    (Join-Path $root 'logs\rehearsal-retention.txt')
  )
  foreach($sentinel in $retentionSentinels){
    [IO.File]::WriteAllText($sentinel,"Rehearsal retention sentinel $operationId",[Text.UTF8Encoding]::new($false))
  }

  $uninstaller=Join-Path $root 'unins000.exe'
  if(-not(Test-Path -LiteralPath $uninstaller -PathType Leaf)){throw 'Installed uninstaller was not found'}
  $uninstallLog=Join-Path $evidence "uninstall-$operationId.log"
  $process=Start-Process -FilePath $uninstaller -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',"/LOG=$uninstallLog") -Wait -PassThru
  if($process.ExitCode-ne0){throw "Uninstaller exited with code $($process.ExitCode)"}
  Add-Phase 'uninstall' 'PASS' 'Uninstaller completed without an application runtime process.'

  $expectedRetention=@($release)+$retentionSentinels
  $missing=@($expectedRetention|Where-Object{-not(Test-Path -LiteralPath $_)})
  if($missing.Count){throw "Uninstall removed protected retained data: $($missing-join', ')"}
  $replaceable=@((Join-Path $root 'runtime\node.exe'),(Join-Path $root 'installer\complete-installation.ps1'))
  $leftover=@($replaceable|Where-Object{Test-Path -LiteralPath $_})
  if($leftover.Count){throw "Uninstall retained replaceable runtime files: $($leftover-join', ')"}
  $result.retainedPaths=@($expectedRetention)
  Add-Phase 'retention' 'PASS' 'Immutable release and protected data roots were retained; replaceable runtime helpers were removed.'
  $result.status='PASS'
} catch {
  $result.status='FAIL';$result.failure=$_.Exception.Message
  Add-Phase 'failure' 'FAIL' $_.Exception.Message
  throw
} finally {
  $result.completedAt=(Get-Date).ToUniversalTime().ToString('o')
  Save-Result
  Write-Output "Installer rehearsal evidence: $resultPath"
}
