param(
  [Parameter(Mandatory=$true)][string]$BaselineReleaseDirectory,
  [Parameter(Mandatory=$true)][string]$CandidateReleaseDirectory,
  [Parameter(Mandatory=$true)][string]$FailureReleaseDirectory,
  [Parameter(Mandatory=$true)][string]$RehearsalReleasePublicKey,
  [Parameter(Mandatory=$true)][string]$NodeExecutable,
  [Parameter(Mandatory=$true)][string]$OutputDirectory
)
$ErrorActionPreference='Stop'
function Get-Sha256([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Assert-OrdinaryTree([string]$Root){
  foreach($item in @(Get-Item -LiteralPath $Root -Force)+@(Get-ChildItem -LiteralPath $Root -Force -Recurse)){
    if(($item.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw "Rehearsal bundle input contains a junction or symbolic link: $($item.FullName)"}
  }
}
function Assert-NoSecretFiles([string]$Root){
  $forbidden=@(Get-ChildItem -LiteralPath $Root -File -Force -Recurse|Where-Object{
    $_.Name-match '^\.env($|\.)'-or$_.Name-match '(?i)^credentials?\.(json|xml|txt)$'-or$_.Name-match '(?i)private.*\.pem$'-or$_.Extension-in@('.pfx','.p12','.key')
  })
  if($forbidden.Count){throw "Release contains forbidden secret-bearing filenames: $(@($forbidden.Name)-join', ')"}
}
$node=[IO.Path]::GetFullPath($NodeExecutable)
$publicKey=[IO.Path]::GetFullPath($RehearsalReleasePublicKey)
$output=[IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\')
foreach($path in @($node,$publicKey)){if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Required bundle input was not found: $path"}}
if(Test-Path -LiteralPath $output){throw 'Bundle output directory must not already exist'}
$roles=[ordered]@{
  baseline=[IO.Path]::GetFullPath($BaselineReleaseDirectory).TrimEnd('\')
  candidate=[IO.Path]::GetFullPath($CandidateReleaseDirectory).TrimEnd('\')
  failure=[IO.Path]::GetFullPath($FailureReleaseDirectory).TrimEnd('\')
}
if(@($roles.Values|Sort-Object -Unique).Count-ne3){throw 'Bundle requires three distinct release directories'}
$sourceRecords=[ordered]@{}
foreach($entry in $roles.GetEnumerator()){
  $release=$entry.Value
  if(-not(Test-Path -LiteralPath $release -PathType Container)){throw "$($entry.Key) release directory was not found"}
  Assert-OrdinaryTree $release;Assert-NoSecretFiles $release
  $standalone=Join-Path $release '.next\standalone';$scripts=Join-Path $release 'scripts'
  $manifest=Join-Path $standalone 'release-manifest.json';$signature=Join-Path $standalone 'release-manifest.sig.json'
  & $node (Join-Path $PSScriptRoot 'release-signing.mjs') verify $manifest $signature $publicKey
  if($LASTEXITCODE-ne0){throw "$($entry.Key) release signature verification failed"}
  & $node (Join-Path $PSScriptRoot 'release-integrity.mjs') verify $standalone $scripts
  if($LASTEXITCODE-ne0){throw "$($entry.Key) release integrity verification failed"}
  $marker=Test-Path -LiteralPath (Join-Path $standalone 'rehearsal-only.json') -PathType Leaf
  if($entry.Key-eq'failure'-and-not$marker){throw 'Failure release must be explicitly marked rehearsal-only'}
  if($entry.Key-ne'failure'-and$marker){throw "$($entry.Key) release cannot be marked rehearsal-only"}
  $metadata=Get-Content -LiteralPath $manifest -Raw|ConvertFrom-Json
  $sourceRecords[$entry.Key]=[ordered]@{commit=$metadata.commit;manifestSha256=Get-Sha256 $manifest;signatureSha256=Get-Sha256 $signature;rehearsalOnly=$marker}
}
New-Item -ItemType Directory -Path $output|Out-Null
try {
  $releaseRoot=Join-Path $output 'releases';$toolRoot=Join-Path $output 'tools';$trustRoot=Join-Path $output 'trust';$evidenceRoot=Join-Path $output 'evidence'
  New-Item -ItemType Directory -Path $releaseRoot,$toolRoot,$trustRoot,$evidenceRoot|Out-Null
  foreach($role in $roles.Keys){Copy-Item -LiteralPath $roles[$role] -Destination (Join-Path $releaseRoot $role) -Recurse}
  $toolNames=@('verify-staging-host.ps1','new-promotion-rehearsal-plan.ps1','run-promotion-rollback-rehearsal.ps1','promote-release.ps1','deployment-task-guards.ps1','deployment-journal.ps1','resolve-node-runtime.ps1','release-signing.mjs','release-integrity.mjs')
  foreach($name in $toolNames){Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination (Join-Path $toolRoot $name)}
  Copy-Item -LiteralPath $publicKey -Destination (Join-Path $trustRoot 'rehearsal-release-public.pem')
  $guide=@'
# Performance Tracker staging rehearsal bundle

This bundle is rehearsal-only. It contains no database credentials, environment files, private signing keys, or production approval.

1. Open an elevated PowerShell session on the approved disposable host.
2. Run `tools\verify-staging-host.ps1` with the exact computer name, an unused NTFS rehearsal root, an external evidence directory, and `-ConfirmDisposableHost`.
3. Copy `releases\baseline`, `releases\candidate`, and `releases\failure` beneath that verified rehearsal root.
4. Create a host-bound plan with `tools\new-promotion-rehearsal-plan.ps1`; record its printed SHA-256 separately.
5. Configure the rehearsal-only scheduled task and protected non-production environment for the baseline/candidate releases.
6. Run `tools\run-promotion-rollback-rehearsal.ps1` with the plan digest and `-ConfirmDisposableHost`.
7. Retain the readiness JSON, plan, plan SHA-256, deployment journal, application logs, and promotion/rollback result JSON.
8. Remove the scheduled task, destroy rehearsal credentials/data, and retain only approved evidence.

Never execute these commands against `C:\PerformanceTracker` or a production database.
'@
  [IO.File]::WriteAllText((Join-Path $output 'README.md'),$guide,[Text.UTF8Encoding]::new($false))
  $checklist=[ordered]@{format='performance-tracker-staging-evidence-checklist-v1';required=@('staging host readiness JSON','host-bound rehearsal plan JSON','independently recorded plan SHA-256','deployment operation journal','sanitized application logs','promotion and rollback rehearsal result JSON','cleanup confirmation')}
  [IO.File]::WriteAllText((Join-Path $output 'evidence-checklist.json'),($checklist|ConvertTo-Json -Depth 4),[Text.UTF8Encoding]::new($false))
  $files=@(Get-ChildItem -LiteralPath $output -File -Recurse|Sort-Object FullName|ForEach-Object{
    [ordered]@{path=$_.FullName.Substring($output.Length+1).Replace('\','/');sha256=Get-Sha256 $_.FullName}
  })
  $bundle=[ordered]@{format='performance-tracker-staging-rehearsal-bundle-v1';rehearsalOnly=$true;createdAt=(Get-Date).ToUniversalTime().ToString('o');publicKeySha256=Get-Sha256 $publicKey;releases=$sourceRecords;files=$files}
  $manifestPath=Join-Path $output 'bundle-manifest.json'
  $stream=[IO.File]::Open($manifestPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
  try{$bytes=[Text.UTF8Encoding]::new($false).GetBytes(($bundle|ConvertTo-Json -Depth 8));$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
} catch {
  if(Test-Path -LiteralPath $output){Remove-Item -LiteralPath $output -Recurse -Force}
  throw
}
Write-Output "Staging rehearsal bundle created: $output"
Write-Output "Bundle manifest SHA-256: $(Get-Sha256 (Join-Path $output 'bundle-manifest.json'))"
