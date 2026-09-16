param(
  [Parameter(Mandatory=$true)][string]$AdminDatabaseUrl,
  [Parameter(Mandatory=$true)][string]$ApplicationDatabaseUrl,
  [Parameter(Mandatory=$true)][string]$ApplicationRole,
  [string]$EvidencePath,
  [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$')][string]$ReleaseId
)
$ErrorActionPreference = 'Stop'
if([string]::IsNullOrWhiteSpace($EvidencePath)-ne[string]::IsNullOrWhiteSpace($ReleaseId)){throw 'EvidencePath and ReleaseId must be supplied together'}
if (-not (Get-Command psql -ErrorAction SilentlyContinue)) { throw 'psql is required' }
if ($ApplicationRole -notmatch '^[a-z_][a-z0-9_]*$') { throw 'ApplicationRole must be a simple PostgreSQL identifier' }
$root = Split-Path $PSScriptRoot -Parent
$migrations = Join-Path $root 'database\migrations'

& psql $AdminDatabaseUrl -v ON_ERROR_STOP=1 -f (Join-Path $migrations '0000_deployment_roles.sql')
if ($LASTEXITCODE -ne 0) { throw 'Role bootstrap migration failed' }
& psql $AdminDatabaseUrl -v ON_ERROR_STOP=1 -c "GRANT mndf_pms_runtime TO $ApplicationRole WITH INHERIT TRUE, SET FALSE"
if ($LASTEXITCODE -ne 0) { throw 'Application runtime-role membership grant failed' }

$owned = Get-ChildItem $migrations -Filter '*.sql' |
  Where-Object { $_.Name -notin @('0000_deployment_roles.sql','0010_deployment_roles.sql') } |
  Sort-Object Name
foreach ($file in $owned) {
  & psql $AdminDatabaseUrl -v ON_ERROR_STOP=1 -c 'SET ROLE mndf_pms_migration_owner' -f $file.FullName
  if ($LASTEXITCODE -ne 0) { throw "Migration failed: $($file.Name)" }
}

& psql $AdminDatabaseUrl -v ON_ERROR_STOP=1 -f (Join-Path $migrations '0010_deployment_roles.sql')
if ($LASTEXITCODE -ne 0) { throw 'Runtime grant migration failed' }
& psql $AdminDatabaseUrl -v ON_ERROR_STOP=1 -f (Join-Path $root 'database\tests\stage_1_1_gate.sql')
if ($LASTEXITCODE -ne 0) { throw 'Stage 1.1 database gate failed' }
& psql $AdminDatabaseUrl -v ON_ERROR_STOP=1 -f (Join-Path $root 'database\tests\records_lifecycle_gate.sql')
if ($LASTEXITCODE -ne 0) { throw 'Records lifecycle database gate failed' }
& psql $AdminDatabaseUrl -v ON_ERROR_STOP=1 -f (Join-Path $root 'database\tests\runtime_rls_smoke.sql')
if ($LASTEXITCODE -ne 0) { throw 'Runtime RLS and audit smoke test failed' }
& psql $ApplicationDatabaseUrl -v ON_ERROR_STOP=1 -c "SELECT current_user,rolbypassrls FROM pg_roles WHERE rolname=current_user"
if ($LASTEXITCODE -ne 0) { throw 'Runtime connection verification failed' }
if($EvidencePath){
  $destination=[IO.Path]::GetFullPath($EvidencePath);$parent=[IO.Path]::GetDirectoryName($destination)
  if(-not(Test-Path -LiteralPath $parent -PathType Container)){throw 'Migration evidence destination directory does not exist'}
  $inventory=@(Get-ChildItem -LiteralPath $migrations -Filter '*.sql' -File|Sort-Object Name|ForEach-Object{[ordered]@{name=$_.Name;sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}})
  $record=[ordered]@{format='performance-tracker-migration-evidence-v1';status='PASS';releaseId=$ReleaseId;completedAt=[DateTimeOffset]::UtcNow.ToString('o');applicationRole=$ApplicationRole;migrations=$inventory;databaseUrlsRecorded=$false}
  $stream=[IO.File]::Open($destination,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
  try{$bytes=[Text.UTF8Encoding]::new($false).GetBytes(($record|ConvertTo-Json -Depth 5));$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
  Write-Output "Migration evidence: $destination"
  Write-Output "Migration evidence SHA-256: $((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant())"
}
