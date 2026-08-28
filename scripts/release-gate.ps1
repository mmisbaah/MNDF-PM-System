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
  [switch]$CodeOnly
)
$ErrorActionPreference="Stop";$project=[System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."));$started=(Get-Date).ToUniversalTime();$checks=[System.Collections.Generic.List[object]]::new();$dbName=$null
function Invoke-GateStep([string]$Name,[scriptblock]$Action){$watch=[Diagnostics.Stopwatch]::StartNew();try{&$Action;$watch.Stop();$checks.Add([ordered]@{name=$Name;status="PASS";seconds=[math]::Round($watch.Elapsed.TotalSeconds,2)})}catch{$watch.Stop();$checks.Add([ordered]@{name=$Name;status="FAIL";seconds=[math]::Round($watch.Elapsed.TotalSeconds,2);error=$_.Exception.Message});throw}}
function With-Database([string]$Url,[string]$Database){$builder=[UriBuilder]$Url;$builder.Path="/$Database";$builder.Uri.AbsoluteUri}
if($PostgresBinDirectory){$bin=[System.IO.Path]::GetFullPath($PostgresBinDirectory);$env:PATH="$bin;$env:PATH"}
$results=[System.IO.Path]::GetFullPath((Join-Path $project $ResultDirectory));New-Item -ItemType Directory -Force -Path $results|Out-Null;$commit=(& git rev-parse HEAD).Trim();$branch=(& git branch --show-current).Trim()
try{
  Invoke-GateStep "Accessibility source policy" {& npm run accessibility:gate;if($LASTEXITCODE-ne0){throw "Accessibility policy validation failed"}}
  Invoke-GateStep "TypeScript" {& npm run typecheck;if($LASTEXITCODE-ne0){throw "TypeScript validation failed"}}
  Invoke-GateStep "Automated tests" {& npm test;if($LASTEXITCODE-ne0){throw "Automated tests failed"}}
  Invoke-GateStep "Production build" {& npm run build;if($LASTEXITCODE-ne0){throw "Production build failed"};& (Join-Path $PSScriptRoot "prepare-standalone.ps1");if($LASTEXITCODE-ne0){throw "Standalone packaging failed"}}
  if(-not$CodeOnly){
    if(-not$AdminMaintenanceUrl-or-not$RuntimeUrl){throw "POSTGRES_ADMIN_URL and DATABASE_URL are required for the disposable database gate"}
    if($ApplicationRole-notmatch'^[a-z_][a-z0-9_]*$'){throw "ApplicationRole must be a simple PostgreSQL identifier"}
    foreach($tool in @("createdb","dropdb","psql")){if(-not(Get-Command $tool -ErrorAction SilentlyContinue)){throw "PostgreSQL utility is required: $tool"}}
    $dbName="mndf_pms_release_verify_$($started.ToString('yyyyMMddHHmmss'))";if($dbName-notmatch'^mndf_pms_release_verify_[0-9]{14}$'){throw "Unsafe disposable database name"};$adminGate=With-Database $AdminMaintenanceUrl $dbName;$runtimeGate=With-Database $RuntimeUrl $dbName
    Invoke-GateStep "Create disposable database" {& createdb --maintenance-db=$AdminMaintenanceUrl $dbName;if($LASTEXITCODE-ne0){throw "Disposable database creation failed"}}
    Invoke-GateStep "Migrations, constraints, RLS, and audit gate" {& (Join-Path $PSScriptRoot "apply-migrations.ps1") -AdminDatabaseUrl $adminGate -ApplicationDatabaseUrl $runtimeGate -ApplicationRole $ApplicationRole;if($LASTEXITCODE-ne0){throw "Database release gate failed"}}
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
  if($dbName){& dropdb --maintenance-db=$AdminMaintenanceUrl --if-exists $dbName|Out-Null}
  $finished=(Get-Date).ToUniversalTime();$result=[ordered]@{format="performance-tracker-release-gate-v1";status=if($failure){"FAIL"}elseif($CodeOnly){"CODE_ONLY_PASS"}else{"PASS"};commit=$commit;branch=$branch;startedAt=$started.ToString("o");finishedAt=$finished.ToString("o");codeOnly=[bool]$CodeOnly;checks=$checks};$path=Join-Path $results "release-gate-$($started.ToString('yyyyMMddTHHmmssZ')).json";$result|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $path -Encoding utf8;Write-Output ($result|ConvertTo-Json -Depth 6 -Compress)
}
if($failure){throw $failure}
