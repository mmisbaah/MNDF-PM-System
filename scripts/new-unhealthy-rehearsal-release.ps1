param(
  [Parameter(Mandatory=$true)][string]$OutputDirectory,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{40}$')][string]$GeneratorCommit,
  [Parameter(Mandatory=$true)][string]$RehearsalSigningPrivateKey,
  [Parameter(Mandatory=$true)][string]$RehearsalSigningPublicKey,
  [string]$NodeExecutable='node'
)
$ErrorActionPreference='Stop'
if([string]::IsNullOrWhiteSpace($env:RELEASE_SIGNING_KEY_PASSPHRASE)-or$env:RELEASE_SIGNING_KEY_PASSPHRASE.Length-lt20){throw 'RELEASE_SIGNING_KEY_PASSPHRASE is required for the rehearsal signing key'}
$output=[IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\')
if(Test-Path -LiteralPath $output){throw 'Failure release output must not already exist'}
$privateKey=[IO.Path]::GetFullPath($RehearsalSigningPrivateKey)
$publicKey=[IO.Path]::GetFullPath($RehearsalSigningPublicKey)
foreach($path in @($privateKey,$publicKey)){if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Rehearsal signing input was not found: $path"}}
$standalone=Join-Path $output '.next\standalone'
$releaseScripts=Join-Path $output 'scripts'
New-Item -ItemType Directory -Path $standalone,$releaseScripts|Out-Null
try {
  $server=@'
const http = require('node:http');
const host = process.env.HOSTNAME || '127.0.0.1';
const port = Number(process.env.PORT || 3100);
const server = http.createServer((request, response) => {
  response.writeHead(request.url === '/api/health' ? 503 : 404, { 'content-type': 'application/json', 'cache-control': 'no-store' });
  response.end(JSON.stringify({ status: 'unhealthy', rehearsalOnly: true }));
});
server.listen(port, host);
'@
  [IO.File]::WriteAllText((Join-Path $standalone 'server.js'),$server,[Text.UTF8Encoding]::new($false))
  $package=[ordered]@{name='performance-tracker-unhealthy-rehearsal';version='0.0.0-rehearsal';private=$true;rehearsalOnly=$true}
  [IO.File]::WriteAllText((Join-Path $standalone 'package.json'),($package|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
  $marker=[ordered]@{
    format='performance-tracker-unhealthy-rehearsal-v1';rehearsalOnly=$true
    purpose='Deliberately returns HTTP 503 to verify automatic deployment rollback.'
    generatorCommit=$GeneratorCommit.ToLowerInvariant();generatedAt=(Get-Date).ToUniversalTime().ToString('o')
  }
  [IO.File]::WriteAllText((Join-Path $standalone 'rehearsal-only.json'),($marker|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
  foreach($name in @('start-production.ps1','application-log-redaction.ps1','validate-production-env.mjs','resolve-node-runtime.ps1','release-signing.mjs','release-integrity.mjs')){
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination (Join-Path $releaseScripts $name)
  }
  & $NodeExecutable (Join-Path $PSScriptRoot 'release-integrity.mjs') create $standalone $releaseScripts $GeneratorCommit.ToLowerInvariant()
  if($LASTEXITCODE-ne0){throw 'Failure release integrity manifest creation failed'}
  $manifest=Join-Path $standalone 'release-manifest.json';$signature=Join-Path $standalone 'release-manifest.sig.json'
  & $NodeExecutable (Join-Path $PSScriptRoot 'release-signing.mjs') sign $manifest $privateKey $signature
  if($LASTEXITCODE-ne0){throw 'Failure release signing failed'}
  & $NodeExecutable (Join-Path $PSScriptRoot 'release-signing.mjs') verify $manifest $signature $publicKey
  if($LASTEXITCODE-ne0){throw 'Failure release signature verification failed'}
  & $NodeExecutable (Join-Path $PSScriptRoot 'release-integrity.mjs') verify $standalone $releaseScripts
  if($LASTEXITCODE-ne0){throw 'Failure release package verification failed'}
} catch {
  if(Test-Path -LiteralPath $output){Remove-Item -LiteralPath $output -Recurse -Force}
  throw
}
Write-Output "Signed unhealthy rehearsal release created: $output"
Write-Output 'This test-only package is not a Performance Tracker production release.'
