param(
  [Parameter(Mandatory=$true)][string]$ReleaseManifestPath,
  [Parameter(Mandatory=$true)][string]$ReleaseGateResultPath,
  [Parameter(Mandatory=$true)][string]$BranchVerificationResultPath,
  [Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$')][string]$ReleaseId,
  [Parameter(Mandatory=$true)][string]$Repository,
  [string]$Branch='main',
  [Parameter(Mandatory=$true)][string]$ReleasePrivateKey,
  [Parameter(Mandatory=$true)][string]$ReleasePublicKey,
  [Parameter(Mandatory=$true)][string]$OutputPath,
  [Parameter(Mandatory=$true)][string]$OutputSignaturePath,
  [string]$NodeExecutable='node',
  [ValidateRange(1,72)][int]$MaximumEvidenceAgeHours=24
)
$ErrorActionPreference='Stop'
function Get-Sha256([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Read-Json([string]$Path,[string]$Label){
  $full=[IO.Path]::GetFullPath($Path);if(-not(Test-Path -LiteralPath $full -PathType Leaf)){throw "$Label was not found"}
  try{return @{Path=$full;Value=(Get-Content -LiteralPath $full -Raw|ConvertFrom-Json)}}catch{throw "$Label is not valid JSON"}
}
if($Repository-notmatch'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'-or$Branch-notmatch'^[A-Za-z0-9._/-]+$'){throw 'Repository or branch is invalid'}
$manifestInput=Read-Json $ReleaseManifestPath 'Release manifest';$gateInput=Read-Json $ReleaseGateResultPath 'Release gate result';$branchInput=Read-Json $BranchVerificationResultPath 'Branch verification result'
$manifest=$manifestInput.Value;$gate=$gateInput.Value;$branchResult=$branchInput.Value
if($manifest.format-ne'performance-tracker-release-package-v3'-or$manifest.commit-notmatch'^[0-9a-f]{40}$'){throw 'Release manifest is not a version 3 release package'}
if($gate.format-ne'performance-tracker-release-gate-v1'-or$gate.status-ne'PASS'-or$gate.codeOnly-ne$false-or$gate.commit-ne$manifest.commit){throw 'A full PASS release gate for the exact manifest commit is required'}
if($branchResult.format-ne'performance-tracker-release-branch-verification-v1'-or$branchResult.status-ne'PASS'-or$branchResult.repository-ne$Repository-or$branchResult.branch-ne$Branch){throw 'Live release-branch verification does not match the approved repository and branch'}
$now=[DateTimeOffset]::UtcNow
foreach($evidence in @(@{Label='Release gate';Value=$gate.finishedAt},@{Label='Branch verification';Value=$branchResult.verifiedAt})){
  if($evidence.Value-is[datetime]){$stamp=[DateTimeOffset]::new(([datetime]$evidence.Value).ToUniversalTime(),[TimeSpan]::Zero)}
  elseif($evidence.Value-is[DateTimeOffset]){$stamp=([DateTimeOffset]$evidence.Value).ToUniversalTime()}
  else{try{$stamp=[DateTimeOffset]::Parse([string]$evidence.Value,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind)}catch{throw "$($evidence.Label) timestamp must be valid UTC"};if($stamp.Offset-ne[TimeSpan]::Zero){throw "$($evidence.Label) timestamp must be valid UTC"}}
  $age=$now-$stamp
  if($age.TotalMinutes-lt-5-or$age.TotalHours-gt$MaximumEvidenceAgeHours){throw "$($evidence.Label) evidence is outside the permitted age"}
}
$privateKey=[IO.Path]::GetFullPath($ReleasePrivateKey);$publicKey=[IO.Path]::GetFullPath($ReleasePublicKey);$output=[IO.Path]::GetFullPath($OutputPath);$signature=[IO.Path]::GetFullPath($OutputSignaturePath)
foreach($path in @($privateKey,$publicKey)){if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Release signing key was not found: $path"}}
if($output-eq$signature-or(Test-Path -LiteralPath $output)-or(Test-Path -LiteralPath $signature)){throw 'Attestation outputs must be distinct new files'}
$record=[ordered]@{
  format='performance-tracker-release-candidate-attestation-v1';status='ATTESTED';createdAt=[DateTimeOffset]::UtcNow.ToString('o')
  releaseId=$ReleaseId;repository=$Repository;branch=$Branch;releaseCommit=[string]$manifest.commit
  releaseManifestSha256=Get-Sha256 $manifestInput.Path;releaseGateSha256=Get-Sha256 $gateInput.Path
  branchVerificationSha256=Get-Sha256 $branchInput.Path;releasePublicKeySha256=Get-Sha256 $publicKey;containsSecrets=$false
}
$stream=[IO.File]::Open($output,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
try{$writer=[IO.StreamWriter]::new($stream,[Text.UTF8Encoding]::new($false));$writer.Write(($record|ConvertTo-Json -Depth 4)+"`n");$writer.Flush()}finally{if($writer){$writer.Dispose()}else{$stream.Dispose()}}
try{
  & $NodeExecutable (Join-Path $PSScriptRoot 'release-signing.mjs') sign $output $privateKey $signature;if($LASTEXITCODE-ne0){throw 'Release candidate attestation signing failed'}
  & $NodeExecutable (Join-Path $PSScriptRoot 'release-signing.mjs') verify $output $signature $publicKey;if($LASTEXITCODE-ne0){throw 'Release candidate attestation signature verification failed'}
}catch{Remove-Item -LiteralPath $output,$signature -Force -ErrorAction SilentlyContinue;throw}
Write-Output "Release candidate attestation SHA-256: $(Get-Sha256 $output)"
