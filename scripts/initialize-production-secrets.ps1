param(
  [Parameter(Mandatory=$true)][string]$OutputPath,
  [Parameter(Mandatory=$true)][string]$DatabaseUrl,
  [Parameter(Mandatory=$true)][string]$AuditDatabaseUrl,
  [Parameter(Mandatory=$true)][string]$EvidenceStorageRoot,
  [Parameter(Mandatory=$true)][string]$EvidenceQuarantineRoot,
  [Parameter(Mandatory=$true)][string]$ServiceAccount,
  [Parameter(Mandatory=$true)][string]$DeploymentAdministrators
)
$ErrorActionPreference="Stop"
$target=[IO.Path]::GetFullPath($OutputPath)
$operator=[Security.Principal.WindowsIdentity]::GetCurrent().Name
if(Test-Path -LiteralPath $target){throw "Refusing to overwrite an existing production environment file: $target"}
foreach($value in @($DatabaseUrl,$AuditDatabaseUrl,$EvidenceStorageRoot,$EvidenceQuarantineRoot,$ServiceAccount,$DeploymentAdministrators)){
  if([string]::IsNullOrWhiteSpace($value)-or$value.Contains("`r")-or$value.Contains("`n")){throw "Parameters must be non-empty single-line values"}
}
function New-Secret([int]$Bytes=48){$buffer=[byte[]]::new($Bytes);[Security.Cryptography.RandomNumberGenerator]::Fill($buffer);[Convert]::ToBase64String($buffer).TrimEnd('=').Replace('+','-').Replace('/','_')}
function Assert-PostgresUrl([string]$Name,[string]$Value){$uri=$null;if(-not[Uri]::TryCreate($Value,[UriKind]::Absolute,[ref]$uri)-or$uri.Scheme-notin@('postgres','postgresql')-or-not$uri.UserInfo.Contains(':')){throw "$Name must be an absolute PostgreSQL URL containing a username and password"}}
Assert-PostgresUrl "DatabaseUrl" $DatabaseUrl
Assert-PostgresUrl "AuditDatabaseUrl" $AuditDatabaseUrl
$mfaBytes=[byte[]]::new(32);[Security.Cryptography.RandomNumberGenerator]::Fill($mfaBytes)
$entries=[ordered]@{
  NODE_ENV="production";DATABASE_URL=$DatabaseUrl;AUTH_JWT_SECRET=(New-Secret);MFA_ENCRYPTION_KEY=[Convert]::ToBase64String($mfaBytes);GRIEVANCE_CRON_SECRET=(New-Secret);EVIDENCE_STORAGE_ROOT=[IO.Path]::GetFullPath($EvidenceStorageRoot);EVIDENCE_QUARANTINE_ROOT=[IO.Path]::GetFullPath($EvidenceQuarantineRoot);EVIDENCE_SCANNER_SECRET=(New-Secret);OPERATIONS_MONITOR_SECRET=(New-Secret);AUDIT_EXPORT_HMAC_KEY=(New-Secret);AUDIT_DATABASE_URL=$AuditDatabaseUrl;HOSTNAME="127.0.0.1";PORT="3100"
}
$parent=Split-Path -Parent $target;if(-not(Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Path $parent|Out-Null}
$temporary="$target.$([guid]::NewGuid().ToString('N')).tmp"
try{
  $content=($entries.GetEnumerator()|ForEach-Object{"$($_.Key)=$($_.Value)"})-join[Environment]::NewLine
  [IO.File]::WriteAllText($temporary,"$content$([Environment]::NewLine)",[Text.UTF8Encoding]::new($false))
  Move-Item -LiteralPath $temporary -Destination $target
  & icacls $target /inheritance:r /grant:r "${ServiceAccount}:(R)" "${DeploymentAdministrators}:(F)" "${operator}:(F)"|Out-Null
  if($LASTEXITCODE-ne0){throw "Failed to apply the protected environment-file ACL"}
  & node "--env-file=$target" (Join-Path $PSScriptRoot "validate-production-env.mjs")
  if($LASTEXITCODE-ne0){throw "Generated production environment failed validation"}
  Write-Output "Production environment created and validated at $target. Secret values were not printed."
}catch{
  if(Test-Path -LiteralPath $temporary){Remove-Item -LiteralPath $temporary -Force}
  if(Test-Path -LiteralPath $target){& icacls $target /grant:r "${operator}:(F)"|Out-Null;Remove-Item -LiteralPath $target -Force}
  throw
}
