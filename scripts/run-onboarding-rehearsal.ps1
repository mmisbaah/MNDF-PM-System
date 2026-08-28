param(
  [Parameter(Mandatory=$true)][string]$AdminDatabaseUrl,
  [string]$BaseUrl="http://127.0.0.1:3100",
  [string]$ResultDirectory="output\onboarding-rehearsals",
  [int]$DurationSeconds=60,
  [switch]$PreDecemberDryRun
)
$ErrorActionPreference="Stop"
$project=[System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$now=(Get-Date).ToUniversalTime()
$localDate=[System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId($now,"West Asia Standard Time").Date
if(-not$PreDecemberDryRun-and($localDate-lt[datetime]"2026-12-01"-or$localDate-gt[datetime]"2026-12-31")){throw "The attended onboarding rehearsal may run only during December 2026. Use -PreDecemberDryRun for engineering validation."}
if(-not(Get-Command psql -ErrorAction SilentlyContinue)){throw "psql is required"}
if(-not$env:ACCEPTANCE_LOGIN_ID-or-not$env:ACCEPTANCE_PASSWORD){throw "Dedicated dummy ACCEPTANCE_LOGIN_ID and ACCEPTANCE_PASSWORD are required"}
$results=[System.IO.Path]::GetFullPath((Join-Path $project $ResultDirectory));New-Item -ItemType Directory -Force -Path $results|Out-Null
$checks=[System.Collections.Generic.List[object]]::new()
function Step([string]$Name,[scriptblock]$Action){$watch=[Diagnostics.Stopwatch]::StartNew();try{&$Action;if($LASTEXITCODE-ne0){throw "$Name failed"};$watch.Stop();$checks.Add([ordered]@{name=$Name;status="PASS";seconds=[math]::Round($watch.Elapsed.TotalSeconds,2)})}catch{$watch.Stop();$checks.Add([ordered]@{name=$Name;status="FAIL";seconds=[math]::Round($watch.Elapsed.TotalSeconds,2);error=$_.Exception.Message});throw}}
try{
  Step "December training-data isolation" {& psql $AdminDatabaseUrl -v ON_ERROR_STOP=1 -c "SET ROLE mndf_pms_migration_owner" -f (Join-Path $project "database\tests\december_training_isolation_gate.sql")}
  Step "40-user authenticated capacity" {$env:CAPACITY_BASE_URL=$BaseUrl;$env:CAPACITY_VIRTUAL_USERS="40";$env:CAPACITY_DURATION_SECONDS="$DurationSeconds";& node (Join-Path $project "scripts\capacity-smoke.mjs")}
}catch{$failure=$_}
$attended=@(
  @{scenario="Personal MFA enrollment on actual pilot devices";status="PENDING"},
  @{scenario="Seven-day Administrator authorization ceremony";status="PENDING"},
  @{scenario="Three-day outgoing Authorizer read/export handover";status="PENDING"},
  @{scenario="Complete appraisal, complaint, correction, acknowledgement, and closure";status="PENDING"},
  @{scenario="Mobile readability and 48px touch-target review";status="PENDING"},
  @{scenario="Evidence scan and quarantine exercise";status="PENDING"},
  @{scenario="Encrypted backup restoration rehearsal";status="PENDING"}
)
$result=[ordered]@{format="performance-tracker-onboarding-rehearsal-v1";automatedStatus=if($failure){"FAIL"}else{"PASS"};overallStatus="PENDING_ATTENDED_SIGNOFF";dryRun=[bool]$PreDecemberDryRun;performedAt=$now.ToString("o");checks=$checks;attendedScenarios=$attended}
$path=Join-Path $results "onboarding-rehearsal-$($now.ToString('yyyyMMddTHHmmssZ')).json";$result|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $path -Encoding utf8;Write-Output($result|ConvertTo-Json -Depth 6 -Compress)
if($failure){throw $failure}
