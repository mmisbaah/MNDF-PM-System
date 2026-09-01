param(
  [Parameter(Mandatory=$true)][string]$OutputPath,
  [Parameter(Mandatory=$true)][string]$DatabaseUrl,
  [Parameter(Mandatory=$true)][string]$AuditDatabaseUrl,
  [Parameter(Mandatory=$true)][string]$EvidenceStorageRoot,
  [Parameter(Mandatory=$true)][string]$EvidenceQuarantineRoot,
  [Parameter(Mandatory=$true)][string]$PublicUrl,
  [Parameter(Mandatory=$true)][string]$ServiceAccount,
  [Parameter(Mandatory=$true)][string]$DeploymentAdministrators
)
$ErrorActionPreference="Stop"
. (Join-Path $PSScriptRoot 'protected-secret-file.ps1')
. (Join-Path $PSScriptRoot 'serialize-production-env.ps1')
$project=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'));. (Join-Path $PSScriptRoot 'resolve-node-runtime.ps1');$node=Resolve-PerformanceTrackerNode -ProjectDirectory $project
$target=[IO.Path]::GetFullPath($OutputPath)
$operator=[Security.Principal.WindowsIdentity]::GetCurrent().Name
if(Test-Path -LiteralPath $target){throw "Refusing to overwrite an existing production environment file: $target"}
foreach($value in @($DatabaseUrl,$AuditDatabaseUrl,$EvidenceStorageRoot,$EvidenceQuarantineRoot,$PublicUrl,$ServiceAccount,$DeploymentAdministrators)){
  if([string]::IsNullOrWhiteSpace($value)-or$value.Contains("`r")-or$value.Contains("`n")){throw "Parameters must be non-empty single-line values"}
}
function New-RandomBytes([int]$Bytes){$buffer=[byte[]]::new($Bytes);$rng=[Security.Cryptography.RandomNumberGenerator]::Create();try{$rng.GetBytes($buffer)}finally{$rng.Dispose()};return ,$buffer}
function New-Secret([int]$Bytes=48){[Convert]::ToBase64String((New-RandomBytes $Bytes)).TrimEnd('=').Replace('+','-').Replace('/','_')}
function Assert-PostgresUrl([string]$Name,[string]$Value){$uri=$null;if(-not[Uri]::TryCreate($Value,[UriKind]::Absolute,[ref]$uri)-or$uri.Scheme-notin@('postgres','postgresql')-or-not$uri.UserInfo.Contains(':')){throw "$Name must be an absolute PostgreSQL URL containing a username and password"}}
Assert-PostgresUrl "DatabaseUrl" $DatabaseUrl
Assert-PostgresUrl "AuditDatabaseUrl" $AuditDatabaseUrl
$publicUri=$null
if(-not[Uri]::TryCreate($PublicUrl,[UriKind]::Absolute,[ref]$publicUri)-or$publicUri.Scheme-ne'https'-or$publicUri.IsLoopback){throw "PublicUrl must be the organization-controlled HTTPS origin"}
$mfaBytes=New-RandomBytes 32
$entries=[ordered]@{
  NODE_ENV="production";DATABASE_URL=$DatabaseUrl;DB_POOL_MAX="15";DB_CONNECT_TIMEOUT_MS="5000";DB_IDLE_TIMEOUT_MS="30000";DB_MAX_LIFETIME_SECONDS="1800";DB_STATEMENT_TIMEOUT_MS="15000";DB_QUERY_TIMEOUT_MS="20000";AUTH_JWT_SECRET=(New-Secret);MFA_ENCRYPTION_KEY=[Convert]::ToBase64String($mfaBytes);GRIEVANCE_CRON_SECRET=(New-Secret);EVIDENCE_STORAGE_ROOT=[IO.Path]::GetFullPath($EvidenceStorageRoot);EVIDENCE_QUARANTINE_ROOT=[IO.Path]::GetFullPath($EvidenceQuarantineRoot);EVIDENCE_SCANNER_SECRET=(New-Secret);OPERATIONS_MONITOR_SECRET=(New-Secret);AUDIT_EXPORT_HMAC_KEY=(New-Secret);AUDIT_DATABASE_URL=$AuditDatabaseUrl;HOSTNAME="127.0.0.1";PORT="3100";PRODUCTION_PUBLIC_URL=$publicUri.GetLeftPart([UriPartial]::Authority);TLS_MIN_CERTIFICATE_DAYS="14"
}
$content=ConvertTo-ProductionEnvironmentFile $entries
Write-ProtectedSecretFile -Path $target -Content $content -ServiceAccount $ServiceAccount -Administrators @('S-1-5-18','S-1-5-32-544',$DeploymentAdministrators,$operator) -Validate {
  param($candidate)
  & $node (Join-Path $PSScriptRoot "validate-production-env.mjs") --config-file $candidate
  if($LASTEXITCODE-ne0){throw 'Generated production environment failed validation'}
}
Write-Output "Production environment created and validated at $target. Secret values were not printed."
