param([string]$OutputDirectory = "backups",[int]$RetentionDays = 30,[string]$PostgresBinDirectory = "")
$ErrorActionPreference = "Stop"
if (-not $env:DATABASE_URL) { throw "DATABASE_URL is required" }
$resolved = [System.IO.Path]::GetFullPath((Join-Path $PWD $OutputDirectory))
New-Item -ItemType Directory -Force -Path $resolved | Out-Null
$stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
$dump = Join-Path $resolved "performance-tracker-$stamp.dump"
$pgDump = if ($PostgresBinDirectory) { Join-Path ([System.IO.Path]::GetFullPath($PostgresBinDirectory)) "pg_dump.exe" } else { "pg_dump" }
if ($PostgresBinDirectory -and -not (Test-Path -LiteralPath $pgDump)) { throw "pg_dump.exe not found in PostgreSQL bin directory" }
& $pgDump --dbname=$env:DATABASE_URL --format=custom --compress=9 --no-owner --no-privileges --file=$dump
if ($LASTEXITCODE -ne 0) { throw "pg_dump failed with exit code $LASTEXITCODE" }
$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $dump).Hash.ToLowerInvariant()
$manifest = "$dump.sha256"
Set-Content -LiteralPath $manifest -Value "$hash  $([System.IO.Path]::GetFileName($dump))" -Encoding ascii
Get-ChildItem -LiteralPath $resolved -Filter "performance-tracker-*.dump" -File | Where-Object LastWriteTimeUtc -lt (Get-Date).ToUniversalTime().AddDays(-$RetentionDays) | ForEach-Object {
  Remove-Item -LiteralPath $_.FullName
  $oldManifest = "$($_.FullName).sha256"; if (Test-Path -LiteralPath $oldManifest) { Remove-Item -LiteralPath $oldManifest }
}
Write-Output $dump
