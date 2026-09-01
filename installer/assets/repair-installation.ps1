param([string]$InstallRoot='C:\PerformanceTracker')
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath($InstallRoot).TrimEnd('\')
$current=Join-Path $root 'current'
$config=Join-Path $root 'config\.env.production.local'
if(-not(Test-Path -LiteralPath $root -PathType Container)){throw "Installation root is missing: $root"}
if(-not(Test-Path -LiteralPath $config -PathType Leaf)){throw 'Protected production configuration is missing; repair will not fabricate secrets'}
if(-not(Test-Path -LiteralPath $current)){throw 'Current release junction is missing; use signed release promotion to restore it'}
$item=Get-Item -LiteralPath $current -Force
if($item.LinkType-ne'Junction'){throw 'Current release path is not the required guarded junction'}
$release=[string]$item.Target
foreach($required in @('.next\standalone\server.js','.next\standalone\release-manifest.json','.next\standalone\release-manifest.sig.json','scripts\start-production.ps1')){
  if(-not(Test-Path -LiteralPath (Join-Path $release $required))){throw "Current release is incomplete: $required"}
}
& node (Join-Path $release 'scripts\validate-production-env.mjs') --config-file $config
if($LASTEXITCODE-ne0){throw 'Protected production configuration failed validation'}
& (Join-Path $release 'scripts\verify-production-acls.ps1') -ReleaseDirectory $release -ConfigDirectory (Join-Path $root 'config') -EvidenceDirectory (Join-Path $root 'evidence') -QuarantineDirectory (Join-Path $root 'quarantine') -LogDirectory (Join-Path $root 'logs')
if($LASTEXITCODE-ne0){throw 'Production ACL verification failed'}
Write-Output 'Performance Tracker installation verification passed. No secrets or release files were replaced.'
