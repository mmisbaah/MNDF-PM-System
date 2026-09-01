param(
  [Parameter(Mandatory=$true)][string]$InstallRoot,
  [Parameter(Mandatory=$true)][string]$ReleaseId,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$TrustedPublicKeySha256,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$TrustedNodeRuntimeSha256
)
$ErrorActionPreference='Stop'
$principal=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if(-not$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Installation completion requires an elevated deployment administrator'}
$root=[IO.Path]::GetFullPath($InstallRoot).TrimEnd('\')
$release=[IO.Path]::GetFullPath((Join-Path $root "releases\$ReleaseId")).TrimEnd('\')
if(-not$release.StartsWith("$root\releases\",[StringComparison]::OrdinalIgnoreCase)){throw 'Release path escaped the installation root'}
if(-not(Test-Path -LiteralPath (Join-Path $release '.next\standalone\server.js'))){throw 'Installed release is incomplete'}
$publicKey=Join-Path $root 'config\release-signing-public.pem'
if(-not(Test-Path -LiteralPath $publicKey -PathType Leaf)){throw 'Trusted release public key is missing'}
$actual=(Get-FileHash -LiteralPath $publicKey -Algorithm SHA256).Hash.ToLowerInvariant()
if($actual-ne$TrustedPublicKeySha256.ToLowerInvariant()){throw 'Installed release public key fingerprint does not match the installer build record'}
$manifest=Join-Path $release '.next\standalone\release-manifest.json'
$signature=Join-Path $release '.next\standalone\release-manifest.sig.json'
$node=Join-Path $root 'runtime\node.exe'
if(-not(Test-Path -LiteralPath $node -PathType Leaf)){throw 'Bundled Node.js runtime is missing'}
$actualNodeHash=(Get-FileHash -LiteralPath $node -Algorithm SHA256).Hash.ToLowerInvariant()
if($actualNodeHash-ne$TrustedNodeRuntimeSha256.ToLowerInvariant()){throw 'Bundled Node.js runtime fingerprint does not match the installer build record'}
& $node (Join-Path $release 'scripts\release-signing.mjs') verify $manifest $signature $publicKey
if($LASTEXITCODE-ne0){throw 'Installed release signature verification failed'}
& $node (Join-Path $release 'scripts\release-integrity.mjs') verify (Join-Path $release '.next\standalone') (Join-Path $release 'scripts')
if($LASTEXITCODE-ne0){throw 'Installed package integrity verification failed'}
$config=Join-Path $root 'config\.env.production.local'
Write-Host 'Performance Tracker files are installed. Secure host provisioning is attended and does not store credentials in installer arguments.'
if(-not(Test-Path -LiteralPath $config)){
  Write-Host 'Production configuration is not present. Run initialize-production-secrets.ps1 after the restricted PostgreSQL roles, HTTPS name, and service account are ready.'
}
Write-Host "Installed immutable release: $release"
Write-Host "Trusted release public-key SHA-256: $actual"
Write-Host 'The application will not start until release signature trust, ACLs, protected configuration, and the dedicated service credential are provisioned.'
