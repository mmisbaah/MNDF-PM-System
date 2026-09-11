param(
  [Parameter(Mandatory=$true)][string]$BaselineReleaseDirectory,
  [Parameter(Mandatory=$true)][string]$CandidateReleaseDirectory,
  [Parameter(Mandatory=$true)][string]$FailureReleaseDirectory,
  [Parameter(Mandatory=$true)][string]$ReleasesRoot,
  [Parameter(Mandatory=$true)][string]$ReleasePublicKey,
  [Parameter(Mandatory=$true)][string]$NodeRuntimeDirectory,
  [Parameter(Mandatory=$true)][string]$OutputPath,
  [ValidateRange(1,14)][int]$ValidDays=7
)
$ErrorActionPreference='Stop'
function Get-Sha256([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
$root=[IO.Path]::GetFullPath($ReleasesRoot).TrimEnd('\')
$publicKey=[IO.Path]::GetFullPath($ReleasePublicKey)
$node=Join-Path ([IO.Path]::GetFullPath($NodeRuntimeDirectory)) 'node.exe'
foreach($path in @($publicKey,$node)){if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Required trust input was not found: $path"}}
$signingHelper=Join-Path $PSScriptRoot 'release-signing.mjs'
$integrityHelper=Join-Path $PSScriptRoot 'release-integrity.mjs'
$roles=[ordered]@{
  baseline=[IO.Path]::GetFullPath($BaselineReleaseDirectory).TrimEnd('\')
  candidate=[IO.Path]::GetFullPath($CandidateReleaseDirectory).TrimEnd('\')
  failure=[IO.Path]::GetFullPath($FailureReleaseDirectory).TrimEnd('\')
}
if(@($roles.Values|Sort-Object -Unique).Count-ne3){throw 'Baseline, candidate, and failure releases must be distinct directories'}
$releaseRecords=[ordered]@{}
foreach($entry in $roles.GetEnumerator()){
  $release=$entry.Value
  if(-not$release.StartsWith("$root\",[StringComparison]::OrdinalIgnoreCase)){throw "$($entry.Key) release must be a child of ReleasesRoot"}
  if(-not(Test-Path -LiteralPath $release -PathType Container)){throw "$($entry.Key) release was not found"}
  $standalone=Join-Path $release '.next\standalone'
  $manifest=Join-Path $standalone 'release-manifest.json'
  $signature="$manifest.sig.json"
  foreach($path in @($manifest,$signature)){if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "$($entry.Key) release integrity evidence is incomplete"}}
  & $node $signingHelper verify $manifest $signature $publicKey
  if($LASTEXITCODE-ne0){throw "$($entry.Key) release signature verification failed"}
  & $node $integrityHelper verify $standalone (Join-Path $release 'scripts')
  if($LASTEXITCODE-ne0){throw "$($entry.Key) release package integrity verification failed"}
  $manifestRecord=Get-Content -LiteralPath $manifest -Raw|ConvertFrom-Json
  if($manifestRecord.commit-notmatch'^[0-9a-f]{40}$'){throw "$($entry.Key) manifest has no valid source commit"}
  $releaseRecords[$entry.Key]=[ordered]@{
    directory=$release;commit=$manifestRecord.commit.ToLowerInvariant()
    manifestSha256=Get-Sha256 $manifest;signatureSha256=Get-Sha256 $signature
  }
}
if(@($releaseRecords.Values.commit|Sort-Object -Unique).Count-ne3){throw 'Baseline, candidate, and failure manifests must identify three distinct source commits'}
$approved=(Get-Date).ToUniversalTime()
$plan=[ordered]@{
  format='performance-tracker-promotion-rehearsal-plan-v1';host=[Environment]::MachineName
  authorizerSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
  approvedAt=$approved.ToString('o');expiresAt=$approved.AddDays($ValidDays).ToString('o')
  releasesRoot=$root;releasePublicKeySha256=Get-Sha256 $publicKey
  releases=$releaseRecords
}
$destination=[IO.Path]::GetFullPath($OutputPath)
$parent=[IO.Path]::GetDirectoryName($destination)
if(-not(Test-Path -LiteralPath $parent -PathType Container)){throw 'Plan output parent directory does not exist'}
$stream=[IO.File]::Open($destination,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
try{$bytes=[Text.UTF8Encoding]::new($false).GetBytes(($plan|ConvertTo-Json -Depth 6));$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
Write-Output "Promotion rehearsal plan created: $destination"
Write-Output "Plan SHA-256: $(Get-Sha256 $destination)"
