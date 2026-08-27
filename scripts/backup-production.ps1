param(
  [Parameter(Mandatory=$true)][string]$PublicKeyFile,
  [Parameter(Mandatory=$true)][string]$OffHostDirectory,
  [string]$DatabaseUrl=$env:BACKUP_DATABASE_URL,
  [string]$EvidenceDirectory="storage\evidence",
  [string]$LocalDirectory="backups",
  [string]$PostgresBinDirectory="",
  [int]$LocalRetentionDays=7,
  [int]$OffHostRetentionDays=90,
  [switch]$AllowSameVolumeForRehearsal
)
$ErrorActionPreference="Stop"
$project=[System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
if(-not $DatabaseUrl){throw "BACKUP_DATABASE_URL is required"}
$publicKey=[System.IO.Path]::GetFullPath($PublicKeyFile);if(-not(Test-Path -LiteralPath $publicKey)){throw "Backup public key not found"}
$offHost=[System.IO.Path]::GetFullPath($OffHostDirectory);$local=[System.IO.Path]::GetFullPath((Join-Path $project $LocalDirectory));$evidence=[System.IO.Path]::GetFullPath((Join-Path $project $EvidenceDirectory))
if($offHost -eq $local -or $offHost.StartsWith($local+[System.IO.Path]::DirectorySeparatorChar)){throw "Off-host directory must be separate from local backup storage"}
if(-not $AllowSameVolumeForRehearsal -and [System.IO.Path]::GetPathRoot($offHost)-eq[System.IO.Path]::GetPathRoot($local)){throw "Off-host retention must use a different volume or network share. Use -AllowSameVolumeForRehearsal only for a non-production test."}
New-Item -ItemType Directory -Force -Path $local,$offHost | Out-Null
$stamp=(Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ");$setName="performance-tracker-$stamp";$staging=Join-Path $local "$setName.partial";$completed=Join-Path $local $setName;$destination=Join-Path $offHost $setName
if((Test-Path $staging)-or(Test-Path $completed)-or(Test-Path $destination)){throw "Backup set already exists"}
New-Item -ItemType Directory -Path $staging | Out-Null
$pgDump=if($PostgresBinDirectory){Join-Path ([System.IO.Path]::GetFullPath($PostgresBinDirectory)) "pg_dump.exe"}else{"pg_dump"};$crypto=Join-Path $PSScriptRoot "backup-crypto.mjs"
$dump=Join-Path $staging "database.dump";$archive=Join-Path $staging "evidence.tar.gz";$dbEncrypted="$dump.ptbk";$evidenceEncrypted="$archive.ptbk";$manifestPath=Join-Path $staging "manifest.json"
try{
  & $pgDump --dbname=$DatabaseUrl --format=custom --compress=9 --no-owner --no-privileges --file=$dump;if($LASTEXITCODE-ne0){throw "pg_dump failed with exit code $LASTEXITCODE"}
  if(Test-Path -LiteralPath $evidence){& tar -czf $archive -C $evidence .}else{$empty=Join-Path $staging "empty-evidence";New-Item -ItemType Directory -Path $empty|Out-Null;& tar -czf $archive -C $empty .}
  if($LASTEXITCODE-ne0){throw "Evidence archive creation failed"}
  & node $crypto encrypt $dump $dbEncrypted $publicKey;if($LASTEXITCODE-ne0){throw "Database encryption failed"}
  & node $crypto encrypt $archive $evidenceEncrypted $publicKey;if($LASTEXITCODE-ne0){throw "Evidence encryption failed"}
  Remove-Item -LiteralPath $dump,$archive
  $dbInfo=Get-Item -LiteralPath $dbEncrypted;$evidenceInfo=Get-Item -LiteralPath $evidenceEncrypted
  $manifest=[ordered]@{format="performance-tracker-backup-set-v1";createdAt=(Get-Date).ToUniversalTime().ToString("o");database=@{file=$dbInfo.Name;bytes=$dbInfo.Length;sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $dbInfo.FullName).Hash.ToLowerInvariant()};evidence=@{file=$evidenceInfo.Name;bytes=$evidenceInfo.Length;sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $evidenceInfo.FullName).Hash.ToLowerInvariant()}}
  $manifest|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $manifestPath -Encoding utf8
  Move-Item -LiteralPath $staging -Destination $completed
  Copy-Item -LiteralPath $completed -Destination $destination -Recurse
  $copiedManifest=Get-Content -LiteralPath (Join-Path $destination "manifest.json") -Raw|ConvertFrom-Json
  foreach($item in @($copiedManifest.database,$copiedManifest.evidence)){$path=Join-Path $destination $item.file;$actual=(Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant();if($actual-ne$item.sha256){throw "Off-host verification failed for $($item.file)"}}
  Get-ChildItem -LiteralPath $local -Directory -Filter "performance-tracker-*"|Where-Object{$_.LastWriteTimeUtc-lt(Get-Date).ToUniversalTime().AddDays(-$LocalRetentionDays)}|Remove-Item -Recurse
  Get-ChildItem -LiteralPath $offHost -Directory -Filter "performance-tracker-*"|Where-Object{$_.LastWriteTimeUtc-lt(Get-Date).ToUniversalTime().AddDays(-$OffHostRetentionDays)}|Remove-Item -Recurse
  $result=[pscustomobject]@{status="SUCCESS";backupSet=$setName;localPath=$completed;offHostPath=$destination;verifiedAt=(Get-Date).ToUniversalTime().ToString("o")};Add-Content -LiteralPath (Join-Path $local "backup-operations.jsonl") -Value ($result|ConvertTo-Json -Compress) -Encoding utf8;$result|ConvertTo-Json -Compress
}catch{if(Test-Path -LiteralPath $staging){Remove-Item -LiteralPath $staging -Recurse};$failure=[pscustomobject]@{status="FAILED";backupSet=$setName;failedAt=(Get-Date).ToUniversalTime().ToString("o");message=$_.Exception.Message};Add-Content -LiteralPath (Join-Path $local "backup-operations.jsonl") -Value ($failure|ConvertTo-Json -Compress) -Encoding utf8;throw}
