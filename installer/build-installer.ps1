param(
  [Parameter(Mandatory=$true)][string]$ReleaseDirectory,
  [Parameter(Mandatory=$true)][string]$ReleaseId,
  [Parameter(Mandatory=$true)][string]$AppVersion,
  [Parameter(Mandatory=$true)][string]$ReleasePublicKey,
  [Parameter(Mandatory=$true)][string]$NodeRuntimeDirectory,
  [string]$CompilerPath,
  [string]$SignToolPath,
  [string]$SigningCertificateThumbprint,
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
$publicKeySha256=(Get-FileHash -LiteralPath $publicKey -Algorithm SHA256).Hash.ToLowerInvariant()
& $nodeExecutable (Join-Path $release 'scripts\release-signing.mjs') verify (Join-Path $release '.next\standalone\release-manifest.json') (Join-Path $release '.next\standalone\release-manifest.sig.json') $publicKey
if($LASTEXITCODE-ne0){throw 'Prepared release signature did not verify against the supplied public key'}
& $nodeExecutable (Join-Path $release 'scripts\release-integrity.mjs') verify (Join-Path $release '.next\standalone') (Join-Path $release 'scripts')
if($LASTEXITCODE-ne0){throw 'Prepared release package integrity verification failed'}
$helpers=@(Get-ChildItem -LiteralPath (Join-Path $release 'scripts') -Filter '*.ps1' -File)
$installerHelpers=@(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'assets') -Filter '*.ps1' -File)
$unsigned=@($helpers+$installerHelpers|Where-Object{(Get-AuthenticodeSignature -LiteralPath $_.FullName).Status-ne'Valid'})
if($unsigned.Count-and-not$AllowUnsignedRehearsal){throw "Production installer requires valid Authenticode signatures on every PowerShell helper. Unsigned or invalid: $($unsigned.Name -join ', ')"}
if(-not$CompilerPath){$command=Get-Command ISCC.exe -ErrorAction SilentlyContinue;if($command){$CompilerPath=$command.Source}}
if(-not$CompilerPath-or-not(Test-Path -LiteralPath $CompilerPath -PathType Leaf)){throw 'Inno Setup compiler ISCC.exe was not found. Install the approved compiler or pass -CompilerPath.'}
$output=[IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $output -Force|Out-Null
$defines=@("/DReleaseSource=$release","/DReleaseId=$ReleaseId","/DAppVersion=$AppVersion","/DReleasePublicKey=$publicKey","/DNodeRuntimeSource=$nodeRuntime","/DTrustedPublicKeySha256=$publicKeySha256","/O$output")
if($AllowUnsignedRehearsal){Write-Warning 'Building an unsigned rehearsal installer. It is not authorized for production distribution.'}
& $CompilerPath @defines (Join-Path $PSScriptRoot 'PerformanceTracker.iss')
if($LASTEXITCODE-ne0){throw "Installer compilation failed with exit code $LASTEXITCODE"}
$installer=Get-ChildItem -LiteralPath $output -Filter "PerformanceTracker-$AppVersion-x64-setup.exe" -File|Select-Object -First 1
if(-not$installer){throw 'Installer compiler completed without the expected executable'}
if(-not$AllowUnsignedRehearsal){
  if($SigningCertificateThumbprint-notmatch'^[0-9a-fA-F]{40,64}$'){throw 'A production Authenticode certificate thumbprint is required'}
  if(-not$SignToolPath){$signCommand=Get-Command signtool.exe -ErrorAction SilentlyContinue;if($signCommand){$SignToolPath=$signCommand.Source}}
  if(-not$SignToolPath-or-not(Test-Path -LiteralPath $SignToolPath -PathType Leaf)){throw 'Windows SDK signtool.exe is required for the production installer'}
  $timestamp=$null
  if(-not[Uri]::TryCreate($TimestampUrl,[UriKind]::Absolute,[ref]$timestamp)-or$timestamp.Scheme-ne'https'){throw 'TimestampUrl must be an absolute HTTPS URL'}
  & $SignToolPath sign /sha1 $SigningCertificateThumbprint /fd SHA256 /tr $TimestampUrl /td SHA256 $installer.FullName
  if($LASTEXITCODE-ne0){throw 'Authenticode signing failed'}
}
$signature=Get-AuthenticodeSignature -LiteralPath $installer.FullName
if(-not$AllowUnsignedRehearsal-and$signature.Status-ne'Valid'){throw 'Compiled production installer does not have a valid Authenticode signature'}
[ordered]@{format='performance-tracker-installer-build-v1';path=$installer.FullName;sha256=(Get-FileHash -LiteralPath $installer.FullName -Algorithm SHA256).Hash.ToLowerInvariant();releaseCommit=$manifest.commit;releaseId=$ReleaseId;version=$AppVersion;nodeRuntimeVersion=$runtimeVersion;nodeRuntimeSha256=(Get-FileHash -LiteralPath $nodeExecutable -Algorithm SHA256).Hash.ToLowerInvariant();releasePublicKeySha256=$publicKeySha256;authenticodeStatus=[string]$signature.Status;productionAuthorized=(-not$AllowUnsignedRehearsal)}|ConvertTo-Json -Depth 3
