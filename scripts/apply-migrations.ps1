param(
  [Parameter(Mandatory=$true)][string]$AdminDatabaseUrl,
  [Parameter(Mandatory=$true)][string]$ApplicationDatabaseUrl,
  [Parameter(Mandatory=$true)][string]$ApplicationRole
)
$ErrorActionPreference = 'Stop'
if (-not (Get-Command psql -ErrorAction SilentlyContinue)) { throw 'psql is required' }
if ($ApplicationRole -notmatch '^[a-z_][a-z0-9_]*$') { throw 'ApplicationRole must be a simple PostgreSQL identifier' }
$root = Split-Path $PSScriptRoot -Parent
$migrations = Join-Path $root 'database\migrations'

& psql $AdminDatabaseUrl -v ON_ERROR_STOP=1 -f (Join-Path $migrations '0000_deployment_roles.sql')
if ($LASTEXITCODE -ne 0) { throw 'Role bootstrap migration failed' }
& psql $AdminDatabaseUrl -v ON_ERROR_STOP=1 -c "GRANT mndf_pms_runtime TO $ApplicationRole"
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
