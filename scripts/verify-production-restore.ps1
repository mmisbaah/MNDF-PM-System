param(
  [Parameter(Mandatory=$true)][string]$BackupSetDirectory,
  [Parameter(Mandatory=$true)][string]$PrivateKeyFile,
  [string]$AdminDatabaseUrl=$env:POSTGRES_ADMIN_URL,
  [string]$PostgresBinDirectory="",
  [string]$ResultDirectory=".verification-backups"
)
$ErrorActionPreference="Stop"
if(-not $env:BACKUP_PRIVATE_KEY_PASSPHRASE){throw "BACKUP_PRIVATE_KEY_PASSPHRASE is required"}
$set=[System.IO.Path]::GetFullPath($BackupSetDirectory);$key=[System.IO.Path]::GetFullPath($PrivateKeyFile);if(-not(Test-Path -LiteralPath $set)){throw "Backup set not found"};if(-not(Test-Path -LiteralPath $key)){throw "Backup private key not found"}
$manifestPath=Join-Path $set "manifest.json";if(-not(Test-Path -LiteralPath $manifestPath)){throw "Backup manifest not found"};$manifest=Get-Content -LiteralPath $manifestPath -Raw|ConvertFrom-Json;if($manifest.format-ne"performance-tracker-backup-set-v1"){throw "Unsupported backup set format"}
foreach($item in @($manifest.database,$manifest.evidence)){$path=Join-Path $set $item.file;if(-not(Test-Path -LiteralPath $path)){throw "Backup component missing: $($item.file)"};$actual=(Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant();if($actual-ne$item.sha256){throw "Backup component checksum mismatch: $($item.file)"}}
$project=[System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."));$results=[System.IO.Path]::GetFullPath((Join-Path $project $ResultDirectory));New-Item -ItemType Directory -Force -Path $results|Out-Null;$run=Join-Path $results "restore-$((Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ'))";New-Item -ItemType Directory -Path $run|Out-Null
$dump=Join-Path $run "database.dump";$archive=Join-Path $run "evidence.tar.gz";$crypto=Join-Path $PSScriptRoot "backup-crypto.mjs"
try{
  & node $crypto decrypt (Join-Path $set $manifest.database.file) $dump $key;if($LASTEXITCODE-ne0){throw "Database decryption failed"}
  & node $crypto decrypt (Join-Path $set $manifest.evidence.file) $archive $key;if($LASTEXITCODE-ne0){throw "Evidence decryption failed"}
  & tar -tzf $archive | Out-Null;if($LASTEXITCODE-ne0){throw "Evidence archive integrity verification failed"}
  $dumpHash=(Get-FileHash -Algorithm SHA256 -LiteralPath $dump).Hash.ToLowerInvariant();Set-Content -LiteralPath "$dump.sha256" -Value "$dumpHash  database.dump" -Encoding ascii
  $restoreOutput=& (Join-Path $PSScriptRoot "verify-restore.ps1") -BackupFile $dump -AdminDatabaseUrl $AdminDatabaseUrl -PostgresBinDirectory $PostgresBinDirectory
  $result=[ordered]@{status="SUCCESS";backupSet=(Split-Path $set -Leaf);verifiedAt=(Get-Date).ToUniversalTime().ToString("o");databaseResult=($restoreOutput -join " ");evidenceArchive="VALID"};$resultPath=Join-Path $results "restore-rehearsal-$((Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')).json";$result|ConvertTo-Json|Set-Content -LiteralPath $resultPath -Encoding utf8;$result|ConvertTo-Json -Compress
}finally{if(Test-Path -LiteralPath $run){Remove-Item -LiteralPath $run -Recurse}}
