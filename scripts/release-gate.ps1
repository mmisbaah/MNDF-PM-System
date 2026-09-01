param(
  [string]$AcceptanceBaseUrl="http://127.0.0.1:3100",
  [string]$AdminMaintenanceUrl=$env:POSTGRES_ADMIN_URL,
  [string]$RuntimeUrl=$env:DATABASE_URL,
  [string]$ApplicationRole="mndf_pms_app",
  [string]$PostgresBinDirectory="",
  [string]$RestoreRehearsalResult="",
  [string]$OperationalReadinessRecord="",
  [string]$ResultDirectory="output\release-gates",
  [int]$MaximumRestoreAgeDays=31,
  [int]$CapacityDurationSeconds=60,
  [int]$LocalDatabasePort=5432,
  [string]$ProductionServiceAccount="",
  [string[]]$ProductionApprovedAdministrators=@(),
  [string]$ProductionReleaseDirectory="",
  [string]$ProductionConfigDirectory="C:\PerformanceTracker\config",
  [string]$ProductionEvidenceDirectory="C:\PerformanceTracker\evidence",
  [string]$ProductionQuarantineDirectory="C:\PerformanceTracker\quarantine",
  [string]$ProductionLogDirectory="C:\PerformanceTracker\logs",
  [switch]$CodeOnly
)
$ErrorActionPreference="Stop";$project=[System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."));$started=(Get-Date).ToUniversalTime();$checks=[System.Collections.Generic.List[object]]::new();$dbName=$null
. (Join-Path $PSScriptRoot 'release-database-ownership.ps1')
$databaseState=$null;$failure=$null
function Invoke-GateStep([string]$Name,[scriptblock]$Action){$watch=[Diagnostics.Stopwatch]::StartNew();try{&$Action;$watch.Stop();$checks.Add([ordered]@{name=$Name;status="PASS";seconds=[math]::Round($watch.Elapsed.TotalSeconds,2)})}catch{$watch.Stop();$checks.Add([ordered]@{name=$Name;status="FAIL";seconds=[math]::Round($watch.Elapsed.TotalSeconds,2);error=$_.Exception.Message});throw}}
function With-Database([string]$Url,[string]$Database){$builder=[UriBuilder]$Url;$builder.Path="/$Database";$builder.Uri.AbsoluteUri}
if($PostgresBinDirectory){$bin=[System.IO.Path]::GetFullPath($PostgresBinDirectory);$env:PATH="$bin;$env:PATH"}
$results=[System.IO.Path]::GetFullPath((Join-Path $project $ResultDirectory));New-Item -ItemType Directory -Force -Path $results|Out-Null;$commit=(& git rev-parse HEAD).Trim();$branch=(& git branch --show-current).Trim()
try{
  Invoke-GateStep "Lint progress regression" {& npm run lint:progress:test;if($LASTEXITCODE-ne0){throw "Lint progress regression failed"}}
  Invoke-GateStep "ESLint" {& npm run lint;if($LASTEXITCODE-ne0){throw "ESLint validation failed"}}
  Invoke-GateStep "Accessibility source policy" {& npm run accessibility:gate;if($LASTEXITCODE-ne0){throw "Accessibility policy validation failed"}}
  Invoke-GateStep "TypeScript" {& npm run typecheck;if($LASTEXITCODE-ne0){throw "TypeScript validation failed"}}
  Invoke-GateStep "Automated tests" {& npm test;if($LASTEXITCODE-ne0){throw "Automated tests failed"}}
  Invoke-GateStep "Production build" {& (Join-Path $PSScriptRoot 'release-build.ps1') -ProjectDirectory $project;& (Join-Path $PSScriptRoot "prepare-standalone.ps1") -ProjectDirectory $project;if($LASTEXITCODE-ne0){throw "Standalone packaging failed"}}
  if(-not$CodeOnly){
    Invoke-GateStep 'Windows deployment regression suite' {& (Join-Path $PSScriptRoot 'deployment-regression-gate.ps1')}
    if([string]::IsNullOrWhiteSpace($ProductionReleaseDirectory)){throw 'ProductionReleaseDirectory must identify the physical release folder, not the current junction'}
    if(-not$AdminMaintenanceUrl-or-not$RuntimeUrl){throw "POSTGRES_ADMIN_URL and DATABASE_URL are required for the disposable database gate"}
    if($ApplicationRole-notmatch'^[a-z_][a-z0-9_]*$'){throw "ApplicationRole must be a simple PostgreSQL identifier"}
    foreach($tool in @("createdb","dropdb","psql")){if(-not(Get-Command $tool -ErrorAction SilentlyContinue)){throw "PostgreSQL utility is required: $tool"}}
    $databaseState=New-ReleaseDatabaseState $AdminMaintenanceUrl
    $dbName=$databaseState.Name;$adminGate=With-Database $AdminMaintenanceUrl $dbName;$runtimeGate=With-Database $RuntimeUrl $dbName
    Invoke-GateStep "Create disposable database" {New-OwnedReleaseDatabase $databaseState}
    Invoke-GateStep "Migrations, constraints, RLS, and audit gate" {& (Join-Path $PSScriptRoot "apply-migrations.ps1") -AdminDatabaseUrl $adminGate -ApplicationDatabaseUrl $runtimeGate -ApplicationRole $ApplicationRole;if($LASTEXITCODE-ne0){throw "Database release gate failed"}}
    $env:PRODUCTION_PUBLIC_URL=$AcceptanceBaseUrl
    Invoke-GateStep "HTTPS, redirect, certificate, and proxy boundary" {& node (Join-Path $PSScriptRoot "verify-tls-boundary.mjs");if($LASTEXITCODE-ne0){throw "TLS boundary verification failed"}}
    Invoke-GateStep "Windows firewall, loopback ports, clock, and scheduled operations" {& (Join-Path $PSScriptRoot "verify-windows-host.ps1") -DatabasePort $LocalDatabasePort;if($LASTEXITCODE-ne0){throw "Windows host readiness verification failed"}}
    if([string]::IsNullOrWhiteSpace($ProductionServiceAccount)){throw "ProductionServiceAccount is required for filesystem ACL verification"}
    if(-not $ProductionApprovedAdministrators.Count){throw 'ProductionApprovedAdministrators must explicitly list approved deployment groups and operators'}
    Invoke-GateStep "Least-privilege production directory ACLs" {& (Join-Path $PSScriptRoot "verify-production-acls.ps1") -ReleaseDirectory $ProductionReleaseDirectory -ConfigDirectory $ProductionConfigDirectory -EvidenceDirectory $ProductionEvidenceDirectory -QuarantineDirectory $ProductionQuarantineDirectory -LogDirectory $ProductionLogDirectory -ServiceAccount $ProductionServiceAccount -ApprovedAdministrators $ProductionApprovedAdministrators;if($LASTEXITCODE-ne0){throw "Production ACL verification failed"}}
    if(-not$env:ACCEPTANCE_LOGIN_ID-or-not$env:ACCEPTANCE_PASSWORD){throw "A dedicated non-MFA ACCEPTANCE_LOGIN_ID and ACCEPTANCE_PASSWORD are required"}
    Invoke-GateStep "Anonymous and authenticated browser/API smoke" {$env:ACCEPTANCE_BASE_URL=$AcceptanceBaseUrl;& node (Join-Path $PSScriptRoot "acceptance-smoke.mjs");if($LASTEXITCODE-ne0){throw "Acceptance smoke failed"}}
    Invoke-GateStep "Authenticated mobile browser regression" {$env:ACCEPTANCE_BASE_URL=$AcceptanceBaseUrl;$env:BROWSER_REGRESSION_OUTPUT=(Join-Path $results "browser-regression");& node (Join-Path $PSScriptRoot "browser-regression.mjs");if($LASTEXITCODE-ne0){throw "Authenticated browser regression failed"}}
    Invoke-GateStep "Adversarial authentication and authorization regression" {$env:SECURITY_BASE_URL=$AcceptanceBaseUrl;& node (Join-Path $PSScriptRoot "security-regression.mjs");if($LASTEXITCODE-ne0){throw "Security regression failed"}}
    Invoke-GateStep "40-user authenticated pilot capacity" {$env:CAPACITY_BASE_URL=$AcceptanceBaseUrl;$env:CAPACITY_VIRTUAL_USERS="40";$env:CAPACITY_DURATION_SECONDS="$CapacityDurationSeconds";& node (Join-Path $PSScriptRoot "capacity-smoke.mjs");if($LASTEXITCODE-ne0){throw "Capacity smoke failed"}}
    if(-not$RestoreRehearsalResult){throw "RestoreRehearsalResult is required"};$restorePath=[System.IO.Path]::GetFullPath($RestoreRehearsalResult);if(-not(Test-Path -LiteralPath $restorePath)){throw "Restoration rehearsal result not found"}
    Invoke-GateStep "Recent restoration rehearsal" {$restore=Get-Content -LiteralPath $restorePath -Raw|ConvertFrom-Json;if($restore.status-ne"SUCCESS"){throw "Restoration rehearsal did not succeed"};$age=$started-([datetime]$restore.verifiedAt).ToUniversalTime();if($age.TotalDays-gt$MaximumRestoreAgeDays-or$age.TotalSeconds-lt0){throw "Restoration rehearsal is outside the permitted age"}}
    if(-not$OperationalReadinessRecord){throw "OperationalReadinessRecord is required"};$readinessPath=[System.IO.Path]::GetFullPath($OperationalReadinessRecord);if(-not(Test-Path -LiteralPath $readinessPath)){throw "Operational readiness record not found"}
    Invoke-GateStep "Training, attended acceptance, support, and launch approval" {& node (Join-Path $PSScriptRoot "validate-operational-readiness.mjs") $readinessPath;if($LASTEXITCODE-ne0){throw "Operational readiness validation failed"}}
  }
}catch{$failure=$_}finally{
  if($databaseState -and $databaseState.Created){
    try {Invoke-GateStep 'Cleanup disposable database' {Remove-OwnedReleaseDatabase $databaseState}} catch {if(-not $failure){$failure=$_}}
  }
  $finished=(Get-Date).ToUniversalTime();$result=[ordered]@{format="performance-tracker-release-gate-v1";status=if($failure){"FAIL"}elseif($CodeOnly){"CODE_ONLY_PASS"}else{"PASS"};commit=$commit;branch=$branch;startedAt=$started.ToString("o");finishedAt=$finished.ToString("o");codeOnly=[bool]$CodeOnly;checks=$checks};$path=Join-Path $results "release-gate-$($started.ToString('yyyyMMddTHHmmssZ')).json";$result|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $path -Encoding utf8;Write-Output ($result|ConvertTo-Json -Depth 6 -Compress)
}
if($failure){throw $failure}
