param([string]$ProjectDirectory=(Split-Path $PSScriptRoot -Parent))
$ErrorActionPreference='Stop'
$project=[IO.Path]::GetFullPath($ProjectDirectory)
. (Join-Path $PSScriptRoot 'release-source-check.ps1')
$commit=Get-CleanReleaseCommit $project
$next=Join-Path $project '.next'
# Never relabel or remove an existing build. Use a fresh release checkout.
if(Test-Path -LiteralPath $next){throw 'Release build requires an absent .next directory. Use a fresh verification/release checkout; existing output was preserved.'}
Push-Location $project
try {
  & node (Join-Path $PSScriptRoot 'materialize-standalone.mjs') check $project
  if($LASTEXITCODE -ne 0){throw 'Release dependency layout check failed'}
  $hadDatabaseUrl=Test-Path Env:DATABASE_URL
  $previousDatabaseUrl=$env:DATABASE_URL
  if(-not$hadDatabaseUrl){$env:DATABASE_URL='postgresql://release_build_only@127.0.0.1:1/release_build'}
  try {
    & npm run build
    if($LASTEXITCODE -ne 0){throw 'Release build failed; no provenance receipt was issued'}
  } finally {
    if($hadDatabaseUrl){$env:DATABASE_URL=$previousDatabaseUrl}else{Remove-Item Env:DATABASE_URL -ErrorAction SilentlyContinue}
  }
  if((Get-CleanReleaseCommit $project) -ne $commit){throw 'Source changed during release build'}
  $standalone=Join-Path $next 'standalone'
  if(-not(Test-Path -LiteralPath (Join-Path $standalone 'server.js'))){throw 'Standalone build output is missing'}
  foreach($asset in @(@{source=(Join-Path $next 'static');target=(Join-Path $standalone '.next\static')},@{source=(Join-Path $project 'public');target=(Join-Path $standalone 'public')})){
    New-Item -ItemType Directory -Path $asset.target -Force | Out-Null
    Get-ChildItem -LiteralPath $asset.source -Force | Copy-Item -Destination $asset.target -Recurse -Force
  }
  & node (Join-Path $PSScriptRoot 'materialize-standalone.mjs') materialize $project
  if($LASTEXITCODE -ne 0){throw 'Standalone dependency materialization failed; raw build preserved'}
  & node (Join-Path $PSScriptRoot 'generate-runtime-sbom.mjs') $standalone $commit
  if($LASTEXITCODE -ne 0){throw 'Runtime SBOM generation failed'}
  & node (Join-Path $PSScriptRoot 'release-integrity.mjs') create $standalone (Join-Path $project 'scripts') $commit
  if($LASTEXITCODE -ne 0){throw 'Build inventory creation failed'}
  if((Get-CleanReleaseCommit $project) -ne $commit){throw 'Source changed while build inventory was captured'}
  & node (Join-Path $PSScriptRoot 'release-build-provenance.mjs') record $project $commit
  if($LASTEXITCODE -ne 0){throw 'Build provenance recording failed'}
  Write-Output "Release build recorded for commit $commit"
} finally {Pop-Location}
