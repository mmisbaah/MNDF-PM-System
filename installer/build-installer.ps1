param(
  [Parameter(Mandatory=$true)][string]$ReleaseDirectory,
  [Parameter(Mandatory=$true)][string]$ReleaseId,
  [Parameter(Mandatory=$true)][string]$AppVersion,
  [Parameter(Mandatory=$true)][string]$ReleasePublicKey,
  [Parameter(Mandatory=$true)][string]$NodeRuntimeDirectory,
  [string]$CompilerPath,
  [ValidatePattern('^[0-9a-fA-F]{64}$')][string]$TrustedCompilerSha256='0a8757031b33777e4c9cbffee40f11a5062b36d25cbe144c1db73b6102b80ad7',
  [string]$SignToolPath,
  [string]$SigningCertificateThumbprint,
  [string]$ReleaseSigningPrivateKey,
  [string]$TimestampUrl='https://timestamp.digicert.com',
  [string]$OutputDirectory=(Join-Path $PSScriptRoot 'output'),
  [switch]$AllowUnsignedRehearsal
)
$ErrorActionPreference='Stop'
$release=[IO.Path]::GetFullPath($ReleaseDirectory).TrimEnd('\')
if($ReleaseId-notmatch'^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$'){throw 'ReleaseId contains unsupported characters'}
if($AppVersion-notmatch'^\d+\.\d+\.\d+([.-][A-Za-z0-9.-]+)?$'){throw 'AppVersion must be a semantic version'}
foreach($required in @('.next\standalone\server.js','.next\standalone\release-manifest.json','.next\standalone\release-manifest.sig.json','scripts\start-production.ps1')){
  if(-not(Test-Path -LiteralPath (Join-Path $release $required) -PathType Leaf)){throw "Prepared release is missing $required"}
}
$manifest=Get-Content -LiteralPath (Join-Path $release '.next\standalone\release-manifest.json') -Raw|ConvertFrom-Json
if($manifest.commit-notmatch'^[0-9a-f]{40}$'){throw 'Release manifest has no valid source commit'}
$publicKey=[IO.Path]::GetFullPath($ReleasePublicKey)
if(-not(Test-Path -LiteralPath $publicKey -PathType Leaf)){throw 'Release public key was not found'}
$nodeRuntime=[IO.Path]::GetFullPath($NodeRuntimeDirectory).TrimEnd('\')
$nodeExecutable=Join-Path $nodeRuntime 'node.exe'
$nodeLicense=Join-Path $nodeRuntime 'LICENSE'
if(-not(Test-Path -LiteralPath $nodeExecutable -PathType Leaf)){throw 'Portable Node.js runtime is missing node.exe'}
if(-not(Test-Path -LiteralPath $nodeLicense -PathType Leaf)){throw 'Portable Node.js runtime is missing its LICENSE file'}
$runtimeVersion=(& $nodeExecutable --version).Trim()
if($LASTEXITCODE-ne0-or$runtimeVersion-notmatch'^v24\.'){throw "Installer runtime must be an approved Node.js 24 release; found $runtimeVersion"}
$nodeRuntimeSha256=(Get-FileHash -LiteralPath $nodeExecutable -Algorithm SHA256).Hash.ToLowerInvariant()
$publicKeySha256=(Get-FileHash -LiteralPath $publicKey -Algorithm SHA256).Hash.ToLowerInvariant()
& $nodeExecutable (Join-Path $release 'scripts\release-signing.mjs') verify (Join-Path $release '.next\standalone\release-manifest.json') (Join-Path $release '.next\standalone\release-manifest.sig.json') $publicKey
if($LASTEXITCODE-ne0){throw 'Prepared release signature did not verify against the supplied public key'}
& $nodeExecutable (Join-Path $release 'scripts\release-integrity.mjs') verify (Join-Path $release '.next\standalone') (Join-Path $release 'scripts')
if($LASTEXITCODE-ne0){throw 'Prepared release package integrity verification failed'}
if(-not$CompilerPath){$command=Get-Command ISCC.exe -ErrorAction SilentlyContinue;if($command){$CompilerPath=$command.Source}}
if(-not$CompilerPath-or-not(Test-Path -LiteralPath $CompilerPath -PathType Leaf)){throw 'Inno Setup compiler ISCC.exe was not found. Install the approved compiler or pass -CompilerPath.'}
$compiler=[IO.Path]::GetFullPath($CompilerPath)
$compilerSha256=(Get-FileHash -LiteralPath $compiler -Algorithm SHA256).Hash.ToLowerInvariant()
if($compilerSha256-ne$TrustedCompilerSha256.ToLowerInvariant()){throw 'Inno Setup compiler fingerprint does not match the approved release-tool version'}
$compilerSignature=Get-AuthenticodeSignature -LiteralPath $compiler
if($compilerSignature.Status-ne'Valid'-or$compilerSignature.SignerCertificate.Subject-notmatch'(^|,\s*)O=Pyrsys B\.V\.(,|$)'){throw 'Inno Setup compiler must have a valid Pyrsys B.V. Authenticode signature'}
$output=[IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $output -Force|Out-Null
$expectedInstaller=Join-Path $output "PerformanceTracker-$AppVersion-x64-setup.exe"
$buildRecordPath="$expectedInstaller.build.json"
$buildRecordSignaturePath="$buildRecordPath.sig.json"
foreach($reservedOutput in @($expectedInstaller,$buildRecordPath,$buildRecordSignaturePath)){
  if(Test-Path -LiteralPath $reservedOutput){throw "Refusing to replace existing installer evidence: $reservedOutput"}
}
$packageRelease=$release
$packageAssets=Join-Path $PSScriptRoot 'assets'
$stage=$null
$productionScriptNames=@(
  'application-log-redaction.ps1','apply-migrations.ps1','backup-crypto.mjs','backup-postgres.ps1','backup-production.ps1',
  'deployment-journal.ps1','deployment-task-guards.ps1','export-audit-ledger.ps1','initialize-production-secrets.ps1',
  'install-application-task.ps1','install-audit-export-task.ps1','install-backup-task.ps1','install-evidence-scan-task.ps1',
  'install-monitor-task.ps1','install-scheduled-jobs-task.ps1','monitor-production.ps1','production-acl-policy.ps1',
  'promote-release.ps1','protected-secret-file.ps1','release-integrity.mjs',
  'release-signing.mjs','resolve-node-runtime.ps1','run-scheduled-jobs.ps1','scan-evidence-defender.ps1','serialize-production-env.ps1',
  'set-production-acls.ps1','start-production.ps1','validate-production-env.mjs',
  'verify-audit-export.ps1','verify-production-acls.ps1','verify-production-restore.ps1','verify-restore.ps1',
  'verify-windows-host.ps1'
)
try {
  if($AllowUnsignedRehearsal){
    Write-Warning 'Building an unsigned rehearsal installer. It is not authorized for production distribution.'
  } else {
    if($SigningCertificateThumbprint-notmatch'^[0-9a-fA-F]{40,64}$'){throw 'A production Authenticode certificate thumbprint is required'}
    $certificate=Get-ChildItem -Path Cert:\CurrentUser\My,Cert:\LocalMachine\My -ErrorAction SilentlyContinue|Where-Object{$_.Thumbprint-eq$SigningCertificateThumbprint-and$_.HasPrivateKey}|Select-Object -First 1
    if(-not$certificate){throw 'The Authenticode certificate and private key were not found in an approved certificate store'}
    if(-not$ReleaseSigningPrivateKey-or-not(Test-Path -LiteralPath $ReleaseSigningPrivateKey -PathType Leaf)){throw 'The offline-custody Ed25519 release-signing private key is required for production staging'}
    if([string]::IsNullOrEmpty($env:RELEASE_SIGNING_KEY_PASSPHRASE)-or$env:RELEASE_SIGNING_KEY_PASSPHRASE.Length-lt20){throw 'RELEASE_SIGNING_KEY_PASSPHRASE is required for production staging'}
    $timestamp=$null
    if(-not[Uri]::TryCreate($TimestampUrl,[UriKind]::Absolute,[ref]$timestamp)-or$timestamp.Scheme-ne'https'){throw 'TimestampUrl must be an absolute HTTPS URL'}
    $stage=Join-Path ([IO.Path]::GetTempPath()) ("PerformanceTracker-installer-stage-"+[guid]::NewGuid().ToString('N'))
    $packageRelease=Join-Path $stage 'release';$packageAssets=Join-Path $stage 'assets'
    New-Item -ItemType Directory -Path $packageRelease,$packageAssets,(Join-Path $packageRelease '.next'),(Join-Path $packageRelease 'scripts')|Out-Null
    Copy-Item -LiteralPath (Join-Path $release '.next\standalone') -Destination (Join-Path $packageRelease '.next') -Recurse
    Copy-Item -LiteralPath (Join-Path $release 'database'),(Join-Path $release 'deploy') -Destination $packageRelease -Recurse
    foreach($scriptName in $productionScriptNames){
      $scriptPath=Join-Path $release "scripts\$scriptName"
      if(-not(Test-Path -LiteralPath $scriptPath -PathType Leaf)){throw "Required production helper is missing: $scriptName"}
      Copy-Item -LiteralPath $scriptPath -Destination (Join-Path $packageRelease 'scripts')
    }
    Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'assets') -Filter '*.ps1' -File|Copy-Item -Destination $packageAssets
    $stageManifest=Join-Path $packageRelease '.next\standalone\release-manifest.json'
    $stageSignature=Join-Path $packageRelease '.next\standalone\release-manifest.sig.json'
    Remove-Item -LiteralPath $stageManifest,$stageSignature -Force
    $stageHelpers=@(Get-ChildItem -LiteralPath (Join-Path $packageRelease 'scripts') -Filter '*.ps1' -File)+@(Get-ChildItem -LiteralPath $packageAssets -Filter '*.ps1' -File)
    foreach($helper in $stageHelpers){
      $signed=Set-AuthenticodeSignature -LiteralPath $helper.FullName -Certificate $certificate -HashAlgorithm SHA256 -TimestampServer $TimestampUrl
      if($signed.Status-ne'Valid'){throw "Authenticode signing failed for staged helper $($helper.Name): $($signed.StatusMessage)"}
    }
    & $nodeExecutable (Join-Path $packageRelease 'scripts\release-integrity.mjs') create (Join-Path $packageRelease '.next\standalone') (Join-Path $packageRelease 'scripts') $manifest.commit
    if($LASTEXITCODE-ne0){throw 'Staged release manifest creation failed'}
    & $nodeExecutable (Join-Path $packageRelease 'scripts\release-signing.mjs') sign $stageManifest ([IO.Path]::GetFullPath($ReleaseSigningPrivateKey)) $stageSignature
    if($LASTEXITCODE-ne0){throw 'Staged release signing failed'}
    & $nodeExecutable (Join-Path $packageRelease 'scripts\release-signing.mjs') verify $stageManifest $stageSignature $publicKey
    if($LASTEXITCODE-ne0){throw 'Staged release signature does not match the supplied public key'}
    & $nodeExecutable (Join-Path $packageRelease 'scripts\release-integrity.mjs') verify (Join-Path $packageRelease '.next\standalone') (Join-Path $packageRelease 'scripts')
    if($LASTEXITCODE-ne0){throw 'Staged signed release integrity verification failed'}
  }
  $defines=@("/DReleaseSource=$packageRelease","/DInstallerAssetsSource=$packageAssets","/DReleaseId=$ReleaseId","/DAppVersion=$AppVersion","/DReleasePublicKey=$publicKey","/DNodeRuntimeSource=$nodeRuntime","/DTrustedPublicKeySha256=$publicKeySha256","/DTrustedNodeRuntimeSha256=$nodeRuntimeSha256","/O$output")
  & $CompilerPath @defines (Join-Path $PSScriptRoot 'PerformanceTracker.iss')
  if($LASTEXITCODE-ne0){throw "Installer compilation failed with exit code $LASTEXITCODE"}
} finally {
  if($stage-and(Test-Path -LiteralPath $stage)){Remove-Item -LiteralPath $stage -Recurse -Force}
}
$installer=Get-Item -LiteralPath $expectedInstaller -ErrorAction SilentlyContinue
if(-not$installer-or$installer.PSIsContainer){throw 'Installer compiler completed without the expected executable'}
if(-not$AllowUnsignedRehearsal){
  if(-not$SignToolPath){$signCommand=Get-Command signtool.exe -ErrorAction SilentlyContinue;if($signCommand){$SignToolPath=$signCommand.Source}}
  if(-not$SignToolPath-or-not(Test-Path -LiteralPath $SignToolPath -PathType Leaf)){throw 'Windows SDK signtool.exe is required for the production installer'}
  & $SignToolPath sign /sha1 $SigningCertificateThumbprint /fd SHA256 /tr $TimestampUrl /td SHA256 $installer.FullName
  if($LASTEXITCODE-ne0){throw 'Authenticode signing failed'}
}
$signature=Get-AuthenticodeSignature -LiteralPath $installer.FullName
if(-not$AllowUnsignedRehearsal-and$signature.Status-ne'Valid'){throw 'Compiled production installer does not have a valid Authenticode signature'}
$allowlistBytes=[Text.Encoding]::UTF8.GetBytes(((@($productionScriptNames|Sort-Object)-join"`n")+"`n"))
$allowlistSha256=[BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($allowlistBytes)).Replace('-','').ToLowerInvariant()
$record=[ordered]@{format='performance-tracker-installer-build-v4';installerFile=[IO.Path]::GetFileName($installer.FullName);recordFile=[IO.Path]::GetFileName($buildRecordPath);recordSignatureFile=if($AllowUnsignedRehearsal){$null}else{[IO.Path]::GetFileName($buildRecordSignaturePath)};sha256=(Get-FileHash -LiteralPath $installer.FullName -Algorithm SHA256).Hash.ToLowerInvariant();releaseCommit=$manifest.commit;releaseId=$ReleaseId;version=$AppVersion;compilerSha256=$compilerSha256;compilerSigner=$compilerSignature.SignerCertificate.Subject;nodeRuntimeVersion=$runtimeVersion;nodeRuntimeSha256=$nodeRuntimeSha256;releasePublicKeySha256=$publicKeySha256;productionHelperAllowlistSha256=$allowlistSha256;authenticodeStatus=[string]$signature.Status;productionAuthorized=(-not$AllowUnsignedRehearsal);createdAt=(Get-Date).ToUniversalTime().ToString('o')}
$recordJson=$record|ConvertTo-Json -Depth 3
$stream=[IO.File]::Open($buildRecordPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
try{$writer=[IO.StreamWriter]::new($stream,[Text.UTF8Encoding]::new($false));$writer.Write($recordJson+"`n");$writer.Flush()}finally{if($writer){$writer.Dispose()}else{$stream.Dispose()}}
if(-not$AllowUnsignedRehearsal){
  & $nodeExecutable (Join-Path $release 'scripts\release-signing.mjs') sign $buildRecordPath ([IO.Path]::GetFullPath($ReleaseSigningPrivateKey)) $buildRecordSignaturePath
  if($LASTEXITCODE-ne0){throw 'Installer provenance signing failed'}
  & $nodeExecutable (Join-Path $release 'scripts\release-signing.mjs') verify $buildRecordPath $buildRecordSignaturePath $publicKey
  if($LASTEXITCODE-ne0){throw 'Installer provenance signature verification failed'}
}
$recordJson
