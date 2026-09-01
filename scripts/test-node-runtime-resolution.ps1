$ErrorActionPreference='Stop'
$project=[IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
. (Join-Path $PSScriptRoot 'resolve-node-runtime.ps1')
$developmentNode=Resolve-PerformanceTrackerNode -ProjectDirectory $project
if((& $developmentNode --version)-notmatch'^v24\.'){throw 'Development fallback did not resolve Node.js 24'}
$testRoot=Join-Path ([IO.Path]::GetTempPath()) "performance-tracker-node-$([guid]::NewGuid().ToString('N'))"
$release=Join-Path $testRoot 'releases\test-release'
try{
  New-Item -ItemType Directory -Path $release -Force|Out-Null
  $failed=$false
  try{Resolve-PerformanceTrackerNode -ProjectDirectory $release|Out-Null}catch{$failed=$_.Exception.Message-match'was not found'}
  if(-not$failed){throw 'Installed releases must not silently fall back to machine PATH when the bundled runtime is missing'}
}finally{if(Test-Path -LiteralPath $testRoot){Remove-Item -LiteralPath $testRoot -Recurse -Force}}
$runtimeConsumers=@('backup-production.ps1','export-audit-ledger.ps1','initialize-production-secrets.ps1','promote-release.ps1','release-gate.ps1','start-production.ps1','verify-audit-export.ps1','verify-production-restore.ps1')
foreach($file in $runtimeConsumers){
  $content=Get-Content -LiteralPath (Join-Path $PSScriptRoot $file) -Raw
  if($content-notmatch'Resolve-PerformanceTrackerNode'){throw "$file does not resolve the approved runtime"}
  if($content-match'&\s+node\b'){throw "$file still depends on machine-wide Node.js"}
}
Write-Output 'Bundled Node.js runtime resolution tests passed.'
