# Ownership means confirmed successful creation by this invocation, not existence.
function New-ReleaseDatabaseState([string]$MaintenanceUrl) {
  return @{Name=('mndf_pms_release_verify_'+[guid]::NewGuid().ToString('N'));MaintenanceUrl=$MaintenanceUrl;Attempted=$false;Created=$false}
}
function Assert-ReleaseDatabaseName([string]$Name) {
  if($Name -cnotmatch '^mndf_pms_release_verify_[0-9a-f]{32}$'){throw 'Unsafe disposable database name'}
}
function New-OwnedReleaseDatabase($State) {
  Assert-ReleaseDatabaseName $State.Name
  if($State.Attempted){throw 'Database creation already attempted; do not reuse this ownership state'}
  $State.Attempted=$true
  & createdb "--maintenance-db=$($State.MaintenanceUrl)" $State.Name
  if($LASTEXITCODE -ne 0){throw "Disposable database creation was not confirmed: $($State.Name). No automatic cleanup is authorized; inspect uncertain server outcomes manually."}
  $State.Created=$true
}
function Remove-OwnedReleaseDatabase($State) {
  if(-not $State.Created){return}
  Assert-ReleaseDatabaseName $State.Name
  & dropdb "--maintenance-db=$($State.MaintenanceUrl)" --if-exists $State.Name
  if($LASTEXITCODE -ne 0){throw "Disposable database cleanup failed: $($State.Name). Operator cleanup is required."}
  $State.Created=$false
}
