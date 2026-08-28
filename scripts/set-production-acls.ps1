param(
  [Parameter(Mandatory=$true)][string]$ReleaseDirectory,
  [Parameter(Mandatory=$true)][string]$ConfigDirectory,
  [Parameter(Mandatory=$true)][string]$EvidenceDirectory,
  [Parameter(Mandatory=$true)][string]$QuarantineDirectory,
  [Parameter(Mandatory=$true)][string]$LogDirectory,
  [Parameter(Mandatory=$true)][string]$ServiceAccount,
  [Parameter(Mandatory=$true)][string]$DeploymentAdministrators
)
$ErrorActionPreference="Stop"
$principal=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if(-not$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw "ACL provisioning must run from an elevated deployment PowerShell session"}
$operator=[Security.Principal.WindowsIdentity]::GetCurrent().Name
foreach($identity in @($ServiceAccount,$DeploymentAdministrators,$operator)){if([string]::IsNullOrWhiteSpace($identity)-or$identity.Contains("`r")-or$identity.Contains("`n")){throw "Account names must be non-empty single-line values"}}
$paths=[ordered]@{release=[IO.Path]::GetFullPath($ReleaseDirectory);config=[IO.Path]::GetFullPath($ConfigDirectory);evidence=[IO.Path]::GetFullPath($EvidenceDirectory);quarantine=[IO.Path]::GetFullPath($QuarantineDirectory);logs=[IO.Path]::GetFullPath($LogDirectory)}
foreach($entry in $paths.GetEnumerator()){
  $root=[IO.Path]::GetPathRoot($entry.Value)
  if($entry.Value.TrimEnd('\')-eq$root.TrimEnd('\')){throw "Refusing to set ACLs on a filesystem root: $($entry.Value)"}
}
if(-not(Test-Path -LiteralPath $paths.release -PathType Container)){throw "Immutable release directory not found: $($paths.release)"}
foreach($name in @('config','evidence','quarantine','logs')){New-Item -ItemType Directory -Path $paths[$name] -Force|Out-Null}
$resolved=$paths.Values|ForEach-Object{[IO.Path]::GetFullPath($_).TrimEnd('\').ToLowerInvariant()}
if(($resolved|Select-Object -Unique).Count-ne$resolved.Count){throw "Production data directories must be distinct"}
function Set-DirectoryAcl([string]$Path,[string]$ServiceRights){
  & icacls $Path /inheritance:r /grant:r "*S-1-5-18:(OI)(CI)(F)" "*S-1-5-32-544:(OI)(CI)(F)" "${DeploymentAdministrators}:(OI)(CI)(F)" "${operator}:(OI)(CI)(F)" "${ServiceAccount}:(OI)(CI)($ServiceRights)"|Out-Null
  if($LASTEXITCODE-ne0){throw "Failed to apply protected ACL to $Path"}
}
Set-DirectoryAcl $paths.release 'RX'
Set-DirectoryAcl $paths.config 'RX'
Set-DirectoryAcl $paths.evidence 'M'
Set-DirectoryAcl $paths.quarantine 'M'
Set-DirectoryAcl $paths.logs 'M'
Write-Output "Production directory ACLs applied. Broad inherited access was removed; secret-file ACLs must still be verified after secret initialization."
