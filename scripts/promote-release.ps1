param(
  [Parameter(Mandatory=$true)][string]$ReleaseDirectory,
  [string]$ReleasesRoot="C:\PerformanceTracker\releases",
  [string]$CurrentLink="C:\PerformanceTracker\current",
  [string]$TaskName="Performance-Tracker-Application",
  [string]$HealthUrl="http://127.0.0.1:3100/api/health",
  [string]$OperationLog="C:\PerformanceTracker\logs\deployment-operations.jsonl",
  [switch]$Initialize
)
$ErrorActionPreference="Stop"
$principal=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if(-not$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw "Release promotion must run from an elevated deployment PowerShell session"}
$root=[IO.Path]::GetFullPath($ReleasesRoot).TrimEnd('\')
$release=[IO.Path]::GetFullPath($ReleaseDirectory).TrimEnd('\')
$current=[IO.Path]::GetFullPath($CurrentLink).TrimEnd('\')
if(-not$release.StartsWith("$root\",[StringComparison]::OrdinalIgnoreCase)){throw "ReleaseDirectory must be a child of ReleasesRoot"}
if($current.StartsWith("$root\",[StringComparison]::OrdinalIgnoreCase)-or$current-eq$root){throw "CurrentLink must be outside the immutable releases directory"}
if(-not(Test-Path -LiteralPath $release -PathType Container)){throw "Release directory not found: $release"}
$standalone=Join-Path $release ".next\standalone"
$manifestPath=Join-Path $standalone "release-manifest.json"
if(-not(Test-Path -LiteralPath $manifestPath)){throw "Release manifest not found"}
$manifest=Get-Content -LiteralPath $manifestPath -Raw|ConvertFrom-Json
if($manifest.format-ne"performance-tracker-release-package-v1"-or$manifest.commit-notmatch'^[0-9a-f]{40}$'){throw "Release manifest is invalid"}
foreach($item in @(@{path=(Join-Path $standalone "server.js");expected=$manifest.serverSha256},@{path=(Join-Path $standalone "package.json");expected=$manifest.packageSha256})){
  if(-not(Test-Path -LiteralPath $item.path)){throw "Release package file is missing: $($item.path)"}
  $actual=(Get-FileHash -LiteralPath $item.path -Algorithm SHA256).Hash.ToLowerInvariant()
  if($actual-ne$item.expected){throw "Release package integrity verification failed: $($item.path)"}
}
$health=[Uri]$HealthUrl
if($health.Scheme-ne"http"-or$health.Host-notin@("127.0.0.1","localhost","::1")){throw "HealthUrl must use loopback HTTP"}
function New-VerifiedJunction([string]$Path,[string]$Target){New-Item -ItemType Junction -Path $Path -Target $Target|Out-Null;$item=Get-Item -LiteralPath $Path;if($item.LinkType-ne"Junction"){throw "Failed to create guarded release junction"}}
function Assert-Junction([string]$Path){$item=Get-Item -LiteralPath $Path -Force;if($item.LinkType-ne"Junction"){throw "Refusing to replace a path that is not a junction: $Path"};$item}
function Wait-Healthy(){for($attempt=1;$attempt-le15;$attempt++){try{$response=Invoke-WebRequest -UseBasicParsing -Uri $HealthUrl -TimeoutSec 5;if($response.StatusCode-eq200){return}}catch{};Start-Sleep -Seconds 2};throw "Application health check did not pass within 30 seconds"}
$logParent=Split-Path -Parent ([IO.Path]::GetFullPath($OperationLog));New-Item -ItemType Directory -Path $logParent -Force|Out-Null
$started=(Get-Date).ToUniversalTime();$status="FAILED";$previousTarget=$null;$temporary="$current.next.$([guid]::NewGuid().ToString('N'))";$previous="$current.previous.$([guid]::NewGuid().ToString('N'))"
try{
  if($Initialize){if(Test-Path -LiteralPath $current){throw "CurrentLink already exists"};New-VerifiedJunction $current $release;$status="INITIALIZED";return}
  $currentItem=Assert-Junction $current;$previousTarget=[string]$currentItem.Target
  $task=Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop
  if(($task.Actions.Arguments-join' ') -notlike"*$current*"){throw "Application task is not configured against the stable CurrentLink"}
  New-VerifiedJunction $temporary $release
  Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
  Rename-Item -LiteralPath $current -NewName (Split-Path -Leaf $previous)
  Rename-Item -LiteralPath $temporary -NewName (Split-Path -Leaf $current)
  Start-ScheduledTask -TaskName $TaskName;Wait-Healthy
  $status="PROMOTED"
  $old=Assert-Junction $previous;Remove-Item -LiteralPath $old.FullName -Force
}catch{
  $failure=$_
  if(-not$Initialize-and(Test-Path -LiteralPath $previous)){
    Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if(Test-Path -LiteralPath $current){$new=Assert-Junction $current;Remove-Item -LiteralPath $new.FullName -Force}
    Rename-Item -LiteralPath $previous -NewName (Split-Path -Leaf $current)
    Start-ScheduledTask -TaskName $TaskName;Wait-Healthy
    $status="ROLLED_BACK"
  }
  throw $failure
}finally{
  if(Test-Path -LiteralPath $temporary){$temp=Assert-Junction $temporary;Remove-Item -LiteralPath $temp.FullName -Force}
  $entry=[ordered]@{format="performance-tracker-deployment-operation-v1";status=$status;occurredAt=$started.ToString("o");releaseCommit=$manifest.commit;releaseDirectory=$release;previousTarget=$previousTarget;operator=[Security.Principal.WindowsIdentity]::GetCurrent().Name}
  Add-Content -LiteralPath $OperationLog -Value ($entry|ConvertTo-Json -Compress) -Encoding utf8
}
