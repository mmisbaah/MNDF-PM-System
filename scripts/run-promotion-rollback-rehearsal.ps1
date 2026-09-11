param(
  [Parameter(Mandatory=$true)][string]$BaselineReleaseDirectory,
  [Parameter(Mandatory=$true)][string]$CandidateReleaseDirectory,
  [Parameter(Mandatory=$true)][string]$FailureReleaseDirectory,
  [Parameter(Mandatory=$true)][string]$ReleasesRoot,
  [Parameter(Mandatory=$true)][string]$CurrentLink,
  [Parameter(Mandatory=$true)][string]$TaskName,
  [Parameter(Mandatory=$true)][string]$HealthUrl,
  [Parameter(Mandatory=$true)][string]$OperationLog,
  [Parameter(Mandatory=$true)][string]$ReleasePublicKey,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$TrustedPublicKeySha256,
  [Parameter(Mandatory=$true)][string]$EvidenceDirectory,
  [Parameter(Mandatory=$true)][string]$RehearsalPlanPath,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ApprovedRehearsalPlanSha256,
  [switch]$ConfirmDisposableHost
)
$ErrorActionPreference='Stop'
function Get-Sha256([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}

if(-not$ConfirmDisposableHost){throw 'Use -ConfirmDisposableHost only on an approved disposable Windows staging host'}
$principal=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if(-not$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Promotion rehearsal requires an elevated deployment-administrator session'}
$root=[IO.Path]::GetFullPath($ReleasesRoot).TrimEnd('\')
$current=[IO.Path]::GetFullPath($CurrentLink).TrimEnd('\')
$productionRoot=[IO.Path]::GetFullPath("$env:SystemDrive\PerformanceTracker").TrimEnd('\')
if($root-eq$productionRoot-or$root.StartsWith("$productionRoot\",[StringComparison]::OrdinalIgnoreCase)){
  throw 'Rehearsal ReleasesRoot must not use the production installation path'
}
if($current-eq$productionRoot-or$current.StartsWith("$productionRoot\",[StringComparison]::OrdinalIgnoreCase)){
  throw 'Rehearsal CurrentLink must not use the production installation path'
}
if(Test-Path -LiteralPath $current){throw 'Rehearsal CurrentLink must not already exist'}
$baseline=[IO.Path]::GetFullPath($BaselineReleaseDirectory).TrimEnd('\')
$candidate=[IO.Path]::GetFullPath($CandidateReleaseDirectory).TrimEnd('\')
$failure=[IO.Path]::GetFullPath($FailureReleaseDirectory).TrimEnd('\')
if(@(@($baseline,$candidate,$failure)|Sort-Object -Unique).Count-ne3){throw 'Baseline, candidate, and failure releases must be distinct directories'}
foreach($release in @($baseline,$candidate,$failure)){
  if(-not$release.StartsWith("$root\",[StringComparison]::OrdinalIgnoreCase)){throw 'Every rehearsal release must be a child of ReleasesRoot'}
  if(-not(Test-Path -LiteralPath $release -PathType Container)){throw "Rehearsal release was not found: $release"}
}
$planPath=[IO.Path]::GetFullPath($RehearsalPlanPath)
if(-not(Test-Path -LiteralPath $planPath -PathType Leaf)){throw 'Approved rehearsal plan was not found'}
if((Get-Sha256 $planPath)-ne$ApprovedRehearsalPlanSha256.ToLowerInvariant()){throw 'Rehearsal plan fingerprint does not match independent approval'}
$plan=Get-Content -LiteralPath $planPath -Raw|ConvertFrom-Json
$expectedPlanFields=@('format','host','authorizerSid','approvedAt','expiresAt','releasesRoot','releasePublicKeySha256','releases')
$actualPlanFields=@($plan.PSObject.Properties.Name|Sort-Object)-join','
if($actualPlanFields-ne(@($expectedPlanFields|Sort-Object)-join',')){throw 'Rehearsal plan schema is incomplete or contains unknown fields'}
if($plan.format-ne'performance-tracker-promotion-rehearsal-plan-v1'){throw 'Unsupported rehearsal plan format'}
if($plan.host-ne[Environment]::MachineName){throw 'Rehearsal plan belongs to a different host'}
if($plan.authorizerSid-notmatch'^S-1-'){throw 'Rehearsal plan must identify its authorizer by immutable SID'}
$approved=[datetime]$plan.approvedAt;$expires=[datetime]$plan.expiresAt;$now=(Get-Date).ToUniversalTime()
if($approved.Kind-ne[DateTimeKind]::Utc-or$expires.Kind-ne[DateTimeKind]::Utc-or$approved-gt$now.AddMinutes(5)-or$expires-le$now-or($expires-$approved).TotalDays-gt14){throw 'Rehearsal plan approval period is invalid or expired'}
if([IO.Path]::GetFullPath([string]$plan.releasesRoot).TrimEnd('\')-ne$root){throw 'Rehearsal plan ReleasesRoot does not match'}
if((Get-Sha256 $ReleasePublicKey)-ne$plan.releasePublicKeySha256){throw 'Rehearsal trust key differs from the approved plan'}
$planned=@{baseline=$baseline;candidate=$candidate;failure=$failure}
foreach($role in $planned.Keys){
  $entry=$plan.releases.$role
  if($null-eq$entry-or[IO.Path]::GetFullPath([string]$entry.directory).TrimEnd('\')-ne$planned[$role]){throw "$role release differs from the approved plan"}
  $expectedReleaseFields=@('directory','commit','manifestSha256','signatureSha256')
  if((@($entry.PSObject.Properties.Name|Sort-Object)-join',')-ne(@($expectedReleaseFields|Sort-Object)-join',')){throw "$role release plan schema is invalid"}
  if($entry.commit-notmatch'^[0-9a-f]{40}$'-or$entry.manifestSha256-notmatch'^[0-9a-f]{64}$'-or$entry.signatureSha256-notmatch'^[0-9a-f]{64}$'){throw "$role release plan fingerprints are invalid"}
  $manifest=Join-Path $planned[$role] '.next\standalone\release-manifest.json';$signature="$manifest.sig.json"
  if((Get-Sha256 $manifest)-ne$entry.manifestSha256-or(Get-Sha256 $signature)-ne$entry.signatureSha256){throw "$role release evidence changed after plan approval"}
}
$health=[Uri]$HealthUrl
if($health.Scheme-ne'http'-or$health.Host-notin@('127.0.0.1','localhost','::1')){throw 'HealthUrl must use loopback HTTP'}
$evidence=[IO.Path]::GetFullPath($EvidenceDirectory)
$journal=[IO.Path]::GetFullPath($OperationLog)
if($evidence.StartsWith("$root\",[StringComparison]::OrdinalIgnoreCase)-or$evidence.StartsWith("$current\",[StringComparison]::OrdinalIgnoreCase)){
  throw 'EvidenceDirectory must be outside releases and CurrentLink'
}
if($journal.StartsWith("$root\",[StringComparison]::OrdinalIgnoreCase)-or$journal.StartsWith("$current\",[StringComparison]::OrdinalIgnoreCase)){
  throw 'OperationLog must be outside releases and CurrentLink'
}
New-Item -ItemType Directory -Path $evidence -Force|Out-Null
$operationId=[guid]::NewGuid().ToString('N')
$resultPath=Join-Path $evidence "promotion-rollback-rehearsal-$operationId.json"
$result=[ordered]@{
  format='performance-tracker-promotion-rollback-rehearsal-v1';operationId=$operationId;status='STARTED'
  startedAt=(Get-Date).ToUniversalTime().ToString('o');completedAt=$null;host=[Environment]::MachineName
  operatorSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
  baselineRelease=$baseline;candidateRelease=$candidate;failureRelease=$failure;currentLink=$current
  phases=[Collections.Generic.List[object]]::new();failure=$null
}
function Add-Phase([string]$Name,[string]$Status,[string]$Detail){
  $result.phases.Add([ordered]@{name=$Name;status=$Status;at=(Get-Date).ToUniversalTime().ToString('o');detail=$Detail})
}
function Save-Result(){[IO.File]::WriteAllText($resultPath,($result|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))}
function Assert-CurrentTarget([string]$Expected){
  $item=Get-Item -LiteralPath $current -Force
  if($item.LinkType-ne'Junction'){throw 'CurrentLink is not a guarded junction'}
  $actual=[IO.Path]::GetFullPath([string]$item.Target).TrimEnd('\')
  if($actual-ne[IO.Path]::GetFullPath($Expected).TrimEnd('\')){throw "CurrentLink target mismatch: $actual"}
}
function Wait-Healthy(){
  for($attempt=1;$attempt-le15;$attempt++){
    try{$response=Invoke-WebRequest -UseBasicParsing -Uri $HealthUrl -TimeoutSec 5;if($response.StatusCode-eq200){return}}catch{}
    if($attempt-lt15){Start-Sleep -Seconds 2}
  }
  throw 'Baseline application did not become healthy'
}
$promoter=Join-Path $PSScriptRoot 'promote-release.ps1'
$common=@{ReleasesRoot=$root;CurrentLink=$current;TaskName=$TaskName;HealthUrl=$HealthUrl;OperationLog=$journal;ReleasePublicKey=$ReleasePublicKey;TrustedPublicKeySha256=$TrustedPublicKeySha256}
try {
  Save-Result
  & $promoter -ReleaseDirectory $baseline @common -Initialize
  Assert-CurrentTarget $baseline
  Start-ScheduledTask -TaskName $TaskName
  Wait-Healthy
  Add-Phase 'baseline' 'PASS' 'Baseline initialized and healthy.'

  & $promoter -ReleaseDirectory $candidate @common
  Assert-CurrentTarget $candidate
  Add-Phase 'promotion' 'PASS' 'Candidate promoted and passed loopback health verification.'

  $failedAsExpected=$false
  try {& $promoter -ReleaseDirectory $failure @common}catch{$failedAsExpected=$true}
  if(-not$failedAsExpected){throw 'Failure candidate unexpectedly promoted successfully'}
  Assert-CurrentTarget $candidate
  $records=@(Get-Content -LiteralPath $journal|Where-Object{$_}|ForEach-Object{$_|ConvertFrom-Json})
  if(-not@($records|Where-Object{$_.status-eq'ROLLED_BACK'}).Count){throw 'Deployment journal did not record successful automatic rollback'}
  Add-Phase 'automatic-rollback' 'PASS' 'Unhealthy release was rejected and CurrentLink returned to the healthy candidate.'
  $result.status='PASS'
} catch {
  $result.status='FAIL';$result.failure=$_.Exception.Message
  Add-Phase 'failure' 'FAIL' $_.Exception.Message
  throw
} finally {
  $result.completedAt=(Get-Date).ToUniversalTime().ToString('o');Save-Result
  Write-Output "Promotion and rollback rehearsal evidence: $resultPath"
}
