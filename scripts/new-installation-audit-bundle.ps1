param(
  [Parameter(Mandatory=$true)][string]$ReceiptPath,
  [Parameter(Mandatory=$true)][string]$ReceiptSignaturePath,
  [Parameter(Mandatory=$true)][string]$ReceiptPublicKey,
  [Parameter(Mandatory=$true)][string]$ReceiptVerifier,
  [Parameter(Mandatory=$true)][string]$ReleaseSigningHelper,
  [Parameter(Mandatory=$true)][string]$NodeExecutable,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ApprovedReceiptSha256,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ApprovedReceiptPublicKeySha256,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ApprovedNodeExecutableSha256,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ApprovedReleaseSigningHelperSha256,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ApprovedReceiptVerifierSha256,
  [Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$')][string]$ExpectedReleaseId,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{40}$')][string]$ExpectedReleaseCommit,
  [Parameter(Mandatory=$true)][string]$ExpectedHost,
  [Parameter(Mandatory=$true)][string]$BundleDirectory,
  [Parameter(Mandatory=$true)][string]$BundleSigningPrivateKey,
  [Parameter(Mandatory=$true)][string]$BundleSigningPublicKey
)
$ErrorActionPreference='Stop'
function Get-Sha256([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Assert-OrdinaryPath([string]$Path){$current=Get-Item -LiteralPath $Path -Force -ErrorAction Stop;while($current){if(($current.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw "Audit bundle source contains a reparse point: $($current.FullName)"};$parent=[IO.Path]::GetDirectoryName($current.FullName);if([string]::IsNullOrWhiteSpace($parent)-or$parent-eq$current.FullName){break};$current=Get-Item -LiteralPath $parent -Force -ErrorAction Stop}}
function Write-NewJson([string]$Path,$Value){$stream=[IO.File]::Open($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read);try{$bytes=[Text.UTF8Encoding]::new($false).GetBytes(($Value|ConvertTo-Json -Depth 7));$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}}
if([string]::IsNullOrWhiteSpace($env:RELEASE_SIGNING_KEY_PASSPHRASE)-or$env:RELEASE_SIGNING_KEY_PASSPHRASE.Length-lt20){throw 'RELEASE_SIGNING_KEY_PASSPHRASE is required for audit-bundle signing'}
$receipt=[IO.Path]::GetFullPath($ReceiptPath);$receiptSignature=[IO.Path]::GetFullPath($ReceiptSignaturePath);$receiptKey=[IO.Path]::GetFullPath($ReceiptPublicKey);$verifier=[IO.Path]::GetFullPath($ReceiptVerifier);$helper=[IO.Path]::GetFullPath($ReleaseSigningHelper);$node=[IO.Path]::GetFullPath($NodeExecutable);$privateKey=[IO.Path]::GetFullPath($BundleSigningPrivateKey);$bundleKey=[IO.Path]::GetFullPath($BundleSigningPublicKey);$bundle=[IO.Path]::GetFullPath($BundleDirectory).TrimEnd('\')
foreach($path in @($receipt,$receiptSignature,$receiptKey,$verifier,$helper,$node,$privateKey,$bundleKey)){if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Audit bundle input was not found: $path"};Assert-OrdinaryPath $path}
if(Test-Path -LiteralPath $bundle){throw 'Audit bundle destination must not already exist'}
if($privateKey.StartsWith("$bundle\",[StringComparison]::OrdinalIgnoreCase)){throw 'Audit bundle private key must remain outside the bundle'}
& $verifier -ReceiptPath $receipt -ReceiptSignaturePath $receiptSignature -ReceiptPublicKey $receiptKey -NodeExecutable $node -ReleaseSigningHelper $helper -ApprovedReceiptSha256 $ApprovedReceiptSha256 -ApprovedReceiptPublicKeySha256 $ApprovedReceiptPublicKeySha256 -ApprovedNodeExecutableSha256 $ApprovedNodeExecutableSha256 -ApprovedReleaseSigningHelperSha256 $ApprovedReleaseSigningHelperSha256 -ApprovedVerifierSha256 $ApprovedReceiptVerifierSha256 -ExpectedReleaseId $ExpectedReleaseId -ExpectedReleaseCommit $ExpectedReleaseCommit -ExpectedHost $ExpectedHost
if($LASTEXITCODE-ne0){throw 'Receipt verification failed before audit bundle creation'}
$nodeSignature=Get-AuthenticodeSignature -LiteralPath $node
if($nodeSignature.Status-ne'Valid'-or$nodeSignature.SignerCertificate.Subject-notmatch'(^|,\s*)O=OpenJS Foundation(,|$)'){throw 'Audit bundle requires an authentic OpenJS Foundation Node.js runtime'}
$nodeVersion=(& $node --version).Trim();if($LASTEXITCODE-ne0-or$nodeVersion-notmatch'^v24\.'){throw 'Audit bundle requires the approved Node.js 24 runtime'}
New-Item -ItemType Directory -Path $bundle|Out-Null
try{
  $copies=[ordered]@{'installation-receipt.json'=$receipt;'installation-receipt.sig.json'=$receiptSignature;'receipt-public.pem'=$receiptKey;'verify-production-installation-receipt.ps1'=$verifier;'release-signing.mjs'=$helper;'bundle-public.pem'=$bundleKey}
  foreach($entry in $copies.GetEnumerator()){Copy-Item -LiteralPath $entry.Value -Destination (Join-Path $bundle $entry.Key)}
  $files=@(Get-ChildItem -LiteralPath $bundle -File|Sort-Object Name|ForEach-Object{[ordered]@{name=$_.Name;sha256=Get-Sha256 $_.FullName}})
  $manifest=[ordered]@{format='performance-tracker-installation-audit-bundle-v1';status='PASS';createdAt=[DateTimeOffset]::UtcNow.ToString('o');releaseId=$ExpectedReleaseId;releaseCommit=$ExpectedReleaseCommit.ToLowerInvariant();host=$ExpectedHost;receiptSha256=$ApprovedReceiptSha256.ToLowerInvariant();receiptPublicKeySha256=$ApprovedReceiptPublicKeySha256.ToLowerInvariant();runtime=[ordered]@{version=$nodeVersion;sha256=$ApprovedNodeExecutableSha256.ToLowerInvariant();signer=$nodeSignature.SignerCertificate.Subject;bundled=$false};files=$files;containsSecrets=$false}
  $manifestPath=Join-Path $bundle 'audit-bundle-manifest.json';$manifestSignature=Join-Path $bundle 'audit-bundle-manifest.sig.json'
  Write-NewJson $manifestPath $manifest
  & $node $helper sign $manifestPath $privateKey $manifestSignature;if($LASTEXITCODE-ne0){throw 'Audit bundle manifest signing failed'}
  & $node $helper verify $manifestPath $manifestSignature (Join-Path $bundle 'bundle-public.pem');if($LASTEXITCODE-ne0){throw 'Audit bundle manifest verification failed'}
}catch{Remove-Item -LiteralPath $bundle -Recurse -Force -ErrorAction SilentlyContinue;throw}
Write-Output "Portable installation audit bundle: $bundle"
Write-Output "Audit manifest SHA-256: $(Get-Sha256 (Join-Path $bundle 'audit-bundle-manifest.json'))"
Write-Output "Audit public-key SHA-256: $(Get-Sha256 (Join-Path $bundle 'bundle-public.pem'))"
