param([Parameter(Mandatory=$true)][string]$BackupFile,[string]$AdminDatabaseUrl=$env:POSTGRES_ADMIN_URL,[string]$PostgresBinDirectory="")
$ErrorActionPreference="Stop"
if(-not $AdminDatabaseUrl){throw "POSTGRES_ADMIN_URL is required and must target an administrative database"}
$dump=[System.IO.Path]::GetFullPath($BackupFile);if(-not(Test-Path -LiteralPath $dump)){throw "Backup file not found"}
$manifest="$dump.sha256";if(-not(Test-Path -LiteralPath $manifest)){throw "SHA-256 manifest not found"}
$expected=((Get-Content -LiteralPath $manifest -Raw).Trim() -split '\s+')[0];$actual=(Get-FileHash -Algorithm SHA256 -LiteralPath $dump).Hash.ToLowerInvariant();if($actual-ne$expected){throw "Backup checksum mismatch"}
$pgBin=if($PostgresBinDirectory){[System.IO.Path]::GetFullPath($PostgresBinDirectory)}else{""}
$createdb=if($pgBin){Join-Path $pgBin "createdb.exe"}else{"createdb"};$pgRestore=if($pgBin){Join-Path $pgBin "pg_restore.exe"}else{"pg_restore"};$psql=if($pgBin){Join-Path $pgBin "psql.exe"}else{"psql"};$dropdb=if($pgBin){Join-Path $pgBin "dropdb.exe"}else{"dropdb"}
if($pgBin){foreach($tool in @($createdb,$pgRestore,$psql,$dropdb)){if(-not(Test-Path -LiteralPath $tool)){throw "PostgreSQL utility not found: $tool"}}}
$dbName="mndf_pms_restore_verify_$((Get-Date).ToUniversalTime().ToString('yyyyMMddHHmmss'))"
if($dbName-notmatch'^mndf_pms_restore_verify_[0-9]{14}$'){throw "Unsafe verification database name"}
$uriBuilder=[System.UriBuilder]$AdminDatabaseUrl;$uriBuilder.Path="/$dbName";$verificationUrl=$uriBuilder.Uri.AbsoluteUri
try{
  & $createdb --maintenance-db=$AdminDatabaseUrl $dbName;if($LASTEXITCODE-ne0){throw "createdb failed"}
  & $pgRestore --dbname=$verificationUrl --no-owner --no-privileges --exit-on-error $dump;if($LASTEXITCODE-ne0){throw "pg_restore failed"}
  $checks=& $psql --dbname=$verificationUrl --tuples-only --no-align --command="SELECT count(*) FROM information_schema.tables WHERE table_schema='public'; SELECT count(*) FROM pg_constraint WHERE contype='f'; SELECT count(*) FROM pg_policies;"
  if($LASTEXITCODE-ne0){throw "verification queries failed"};$values=@($checks|Where-Object{$_-match'^\d+$'}|ForEach-Object{[int]$_});if($values.Count-lt3-or$values[0]-lt20-or$values[1]-lt20-or$values[2]-lt10){throw "restored database failed structural thresholds"}
  Write-Output "Restore verified: $($values[0]) tables, $($values[1]) foreign keys, $($values[2]) RLS policies"
}finally{& $dropdb --maintenance-db=$AdminDatabaseUrl --if-exists $dbName}
