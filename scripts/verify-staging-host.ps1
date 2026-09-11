param(
  [Parameter(Mandatory=$true)][string]$ExpectedMachineName,
  [Parameter(Mandatory=$true)][string]$RehearsalRoot,
  [Parameter(Mandatory=$true)][string]$EvidenceDirectory,
  [int]$ApplicationPort=3100,
  [int]$MinimumFreeSpaceGB=5,
  [string[]]$ReservedTaskNames=@(
    'Performance-Tracker-Application',
    'Performance-Tracker-Scheduled-Jobs',
    'Performance-Tracker-Evidence-Scanner',
    'Performance-Tracker-Daily-Backup',
    'Performance-Tracker-Audit-Export',
    'Performance-Tracker-Operations-Monitor'
  ),
  [switch]$ConfirmDisposableHost
)
$ErrorActionPreference='Stop'
if(-not$ConfirmDisposableHost){throw 'Use -ConfirmDisposableHost only after confirming this is a disposable Windows staging host'}
if($ExpectedMachineName-ne[Environment]::MachineName){throw 'ExpectedMachineName does not match the current host'}
if($ApplicationPort-lt1-or$ApplicationPort-gt65535){throw 'ApplicationPort must be between 1 and 65535'}
if($MinimumFreeSpaceGB-lt1){throw 'MinimumFreeSpaceGB must be positive'}
$principal=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if(-not$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Staging-host verification requires an elevated deployment-administrator session'}

$root=[IO.Path]::GetFullPath($RehearsalRoot).TrimEnd('\')
$evidence=[IO.Path]::GetFullPath($EvidenceDirectory).TrimEnd('\')
$productionRoot=[IO.Path]::GetFullPath("$env:SystemDrive\PerformanceTracker").TrimEnd('\')
$systemRoot=[IO.Path]::GetFullPath("$env:SystemDrive\").TrimEnd('\')
if($root-eq$systemRoot-or$root-eq$productionRoot-or$root.StartsWith("$productionRoot\",[StringComparison]::OrdinalIgnoreCase)){
  throw 'RehearsalRoot must not be the system root or production installation path'
}
if($evidence.StartsWith("$root\",[StringComparison]::OrdinalIgnoreCase)-or$evidence-eq$root){throw 'EvidenceDirectory must be outside RehearsalRoot'}
if(Test-Path -LiteralPath $root){throw 'RehearsalRoot must not already exist'}

$failures=[Collections.Generic.List[string]]::new()
$checks=[Collections.Generic.List[object]]::new()
function Add-Check([string]$Name,[bool]$Passed,[string]$Detail){
  $checks.Add([ordered]@{name=$Name;status=if($Passed){'PASS'}else{'FAIL'};detail=$Detail})
  if(-not$Passed){$failures.Add("$Name`: $Detail")}
}
function Find-ExistingAncestor([string]$Path){
  $candidate=$Path
  while(-not(Test-Path -LiteralPath $candidate)){
    $parent=[IO.Path]::GetDirectoryName($candidate)
    if([string]::IsNullOrWhiteSpace($parent)-or$parent-eq$candidate){throw "No existing ancestor for $Path"}
    $candidate=$parent
  }
  [IO.Path]::GetFullPath($candidate)
}

$ancestor=Find-ExistingAncestor $root
$cursor=Get-Item -LiteralPath $ancestor -Force
$redirected=$false
while($cursor){
  if(($cursor.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){$redirected=$true;break}
  $parent=[IO.Path]::GetDirectoryName($cursor.FullName)
  if([string]::IsNullOrWhiteSpace($parent)-or$parent-eq$cursor.FullName){break}
  $cursor=Get-Item -LiteralPath $parent -Force
}
Add-Check 'ordinary staging path' (-not$redirected) 'Existing staging-path ancestors must contain no junctions or symbolic links.'
$drive=[IO.Path]::GetPathRoot($root)
$volume=Get-Volume -DriveLetter $drive.Substring(0,1) -ErrorAction Stop
Add-Check 'NTFS staging volume' ($volume.FileSystem-eq'NTFS') "Detected filesystem: $($volume.FileSystem)"
$freeGB=[math]::Round($volume.SizeRemaining/1GB,2)
Add-Check 'staging capacity' ($freeGB-ge$MinimumFreeSpaceGB) "Free space: $freeGB GB; required: $MinimumFreeSpaceGB GB"
Add-Check 'production root absent' (-not(Test-Path -LiteralPath $productionRoot)) "Production path must not exist on a disposable host: $productionRoot"
$listeners=@(Get-NetTCPConnection -State Listen -LocalPort $ApplicationPort -ErrorAction SilentlyContinue)
Add-Check 'application port free' ($listeners.Count-eq0) "Port $ApplicationPort must have no listener before rehearsal."
$existingTasks=@($ReservedTaskNames|Where-Object{Get-ScheduledTask -TaskName $_ -ErrorAction SilentlyContinue})
Add-Check 'production tasks absent' ($existingTasks.Count-eq0) $(if($existingTasks.Count){"Found: $($existingTasks-join', ')"}else{'No reserved production tasks found.'})
$os=Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
Add-Check 'supported Windows host' ([Environment]::OSVersion.Platform-eq[PlatformID]::Win32NT) "$($os.Caption) $($os.Version)"

New-Item -ItemType Directory -Path $evidence -Force|Out-Null
$evidenceItem=Get-Item -LiteralPath $evidence -Force
if(($evidenceItem.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw 'EvidenceDirectory cannot be a junction or symbolic link'}
$checked=(Get-Date).ToUniversalTime()
$result=[ordered]@{
  format='performance-tracker-staging-host-readiness-v1';status=if($failures.Count){'FAIL'}else{'PASS'}
  checkedAt=$checked.ToString('o');host=[Environment]::MachineName
  operatorSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
  rehearsalRoot=$root;evidenceDirectory=$evidence;applicationPort=$ApplicationPort
  checks=@($checks.ToArray());failures=@($failures.ToArray())
}
$resultPath=Join-Path $evidence "staging-host-readiness-$($checked.ToString('yyyyMMddTHHmmssZ'))-$([guid]::NewGuid().ToString('N')).json"
$stream=[IO.File]::Open($resultPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
try {
  $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($result|ConvertTo-Json -Depth 6))
  $stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)
} finally {$stream.Dispose()}
Write-Output "Staging-host readiness evidence: $resultPath"
if($failures.Count){throw ($failures-join[Environment]::NewLine)}

