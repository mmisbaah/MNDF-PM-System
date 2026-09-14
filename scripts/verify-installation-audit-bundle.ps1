param(
  [Parameter(Mandatory=$true)][string]$BundleDirectory,
  [Parameter(Mandatory=$true)][string]$NodeExecutable,
  [Parameter(Mandatory=$true)][string]$ExternalReleaseSigningHelper,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ApprovedVerifierSha256,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ApprovedManifestSha256,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ApprovedBundlePublicKeySha256,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ApprovedNodeExecutableSha256,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ApprovedExternalSigningHelperSha256,
  [Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$')][string]$ExpectedReleaseId,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{40}$')][string]$ExpectedReleaseCommit,
  [Parameter(Mandatory=$true)][string]$ExpectedHost
)
$ErrorActionPreference='Stop'
function Get-Sha256([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Assert-OrdinaryPath([string]$Path){$current=Get-Item -LiteralPath $Path -Force -ErrorAction Stop;while($current){if(($current.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw "Audit verification path contains a reparse point: $($current.FullName)"};$parent=[IO.Path]::GetDirectoryName($current.FullName);if([string]::IsNullOrWhiteSpace($parent)-or$parent-eq$current.FullName){break};$current=Get-Item -LiteralPath $parent -Force -ErrorAction Stop}}
$verifier=[IO.Path]::GetFullPath($MyInvocation.MyCommand.Path);$bundle=[IO.Path]::GetFullPath($BundleDirectory).TrimEnd('\');$node=[IO.Path]::GetFullPath($NodeExecutable);$externalHelper=[IO.Path]::GetFullPath($ExternalReleaseSigningHelper)
foreach($external in @($verifier,$node,$externalHelper)){if(-not(Test-Path -LiteralPath $external -PathType Leaf)){throw "Approved external verifier input was not found: $external"};if($external.StartsWith("$bundle\",[StringComparison]::OrdinalIgnoreCase)){throw 'Initial audit trust inputs must remain outside the bundle'};Assert-OrdinaryPath $external}
if(-not(Test-Path -LiteralPath $bundle -PathType Container)){throw 'Audit bundle directory was not found'};Assert-OrdinaryPath $bundle
$expectedNames=@('audit-bundle-manifest.json','audit-bundle-manifest.sig.json','bundle-public.pem','installation-receipt.json','installation-receipt.sig.json','receipt-public.pem','release-signing.mjs','verify-production-installation-receipt.ps1')
$items=@(Get-ChildItem -LiteralPath $bundle -Force)
if(@($items|Where-Object{$_.PSIsContainer}).Count){throw 'Audit bundle must not contain directories'}
if((@($items.Name|Sort-Object)-join',')-ne(@($expectedNames|Sort-Object)-join',')){throw 'Audit bundle has added, missing, or unexpected files'}
$paths=@($verifier,$node,$externalHelper)+@($expectedNames|ForEach-Object{Join-Path $bundle $_});$streams=[Collections.Generic.List[IO.FileStream]]::new()
try{
  foreach($path in $paths){Assert-OrdinaryPath $path;$streams.Add([IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read))}
  if((Get-Sha256 $verifier)-ne$ApprovedVerifierSha256.ToLowerInvariant()){throw 'Audit bundle verifier fingerprint does not match independent approval'}
  if((Get-Sha256 $node)-ne$ApprovedNodeExecutableSha256.ToLowerInvariant()){throw 'Audit Node.js fingerprint does not match independent approval'}
  if((Get-Sha256 $externalHelper)-ne$ApprovedExternalSigningHelperSha256.ToLowerInvariant()){throw 'External signing-helper fingerprint does not match independent approval'}
  $manifest=Join-Path $bundle 'audit-bundle-manifest.json';$manifestSignature=Join-Path $bundle 'audit-bundle-manifest.sig.json';$bundleKey=Join-Path $bundle 'bundle-public.pem'
  if((Get-Sha256 $manifest)-ne$ApprovedManifestSha256.ToLowerInvariant()){throw 'Audit bundle manifest fingerprint does not match independent approval'}
  if((Get-Sha256 $bundleKey)-ne$ApprovedBundlePublicKeySha256.ToLowerInvariant()){throw 'Audit bundle public-key fingerprint does not match independent approval'}
  $nodeSignature=Get-AuthenticodeSignature -LiteralPath $node
  if($nodeSignature.Status-ne'Valid'-or$nodeSignature.SignerCertificate.Subject-notmatch'(^|,\s*)O=OpenJS Foundation(,|$)'){throw 'Audit verification requires an authentic OpenJS Foundation Node.js runtime'}
  & $node $externalHelper verify $manifest $manifestSignature $bundleKey;if($LASTEXITCODE-ne0){throw 'Audit bundle manifest signature verification failed'}
  try{$record=Get-Content -LiteralPath $manifest -Raw|ConvertFrom-Json}catch{throw 'Audit bundle manifest is not valid JSON'}
  $required=@('format','status','createdAt','releaseId','releaseCommit','host','receiptSha256','receiptPublicKeySha256','runtime','files','containsSecrets')
  $actualManifestFields=@($record.PSObject.Properties.Name|Sort-Object)-join','
  $expectedManifestFields=@($required|Sort-Object)-join','
  if($actualManifestFields -ne $expectedManifestFields){throw 'Audit bundle manifest schema is incomplete or contains unknown fields'}
  if($record.format -ne 'performance-tracker-installation-audit-bundle-v1' -or $record.status -ne 'PASS' -or $record.containsSecrets -ne $false){throw 'Audit bundle manifest is not a passed, redacted record'}
  if($record.releaseId -ne $ExpectedReleaseId -or $record.releaseCommit -ne $ExpectedReleaseCommit.ToLowerInvariant() -or $record.host -ne $ExpectedHost){throw 'Audit bundle belongs to another deployment'}
  $runtimeFields=@('version','sha256','signer','bundled')
  $actualRuntimeFields=@($record.runtime.PSObject.Properties.Name|Sort-Object)-join','
  $expectedRuntimeFields=@($runtimeFields|Sort-Object)-join','
  $actualNodeVersion=(& $node --version|Out-String).Trim()
  if($actualRuntimeFields -ne $expectedRuntimeFields -or $record.runtime.sha256 -ne $ApprovedNodeExecutableSha256.ToLowerInvariant() -or $record.runtime.bundled -ne $false -or $record.runtime.version -ne $actualNodeVersion -or $record.runtime.signer -ne $nodeSignature.SignerCertificate.Subject){throw 'Audit bundle runtime identity does not match the approved external runtime'}
  $payloadNames=@($expectedNames|Where-Object{$_-notmatch'^audit-bundle-manifest'})
  $actualPayloadNames=@($record.files.name|Sort-Object)-join','
  $expectedPayloadNames=@($payloadNames|Sort-Object)-join','
  if(@($record.files).Count -ne $payloadNames.Count -or $actualPayloadNames -ne $expectedPayloadNames){throw 'Audit bundle inventory is incomplete or contains unknown files'}
  foreach($entry in @($record.files)){if($entry.PSObject.Properties.Count -ne 2 -or $entry.name -notin $payloadNames -or $entry.sha256 -notmatch '^[0-9a-f]{64}$' -or (Get-Sha256 (Join-Path $bundle $entry.name)) -ne $entry.sha256){throw "Audit bundle file failed inventory verification: $($entry.name)"}}
  $receiptVerifier=Join-Path $bundle 'verify-production-installation-receipt.ps1';$receiptHelper=Join-Path $bundle 'release-signing.mjs';$receiptKey=Join-Path $bundle 'receipt-public.pem';$receiptPath=Join-Path $bundle 'installation-receipt.json';$receiptSignature=Join-Path $bundle 'installation-receipt.sig.json'
  $receiptVerifierHash=Get-Sha256 $receiptVerifier;$receiptHelperHash=Get-Sha256 $receiptHelper
  & $receiptVerifier -ReceiptPath $receiptPath -ReceiptSignaturePath $receiptSignature -ReceiptPublicKey $receiptKey -NodeExecutable $node -ReleaseSigningHelper $receiptHelper -ApprovedReceiptSha256 $record.receiptSha256 -ApprovedReceiptPublicKeySha256 $record.receiptPublicKeySha256 -ApprovedNodeExecutableSha256 $ApprovedNodeExecutableSha256 -ApprovedReleaseSigningHelperSha256 $receiptHelperHash -ApprovedVerifierSha256 $receiptVerifierHash -ExpectedReleaseId $ExpectedReleaseId -ExpectedReleaseCommit $ExpectedReleaseCommit -ExpectedHost $ExpectedHost
  if($LASTEXITCODE-ne0){throw 'Bundled production receipt verification failed'}
}finally{for($index=$streams.Count-1;$index-ge0;$index--){$streams[$index].Dispose()}}
Write-Output "Installation audit bundle verified: $ApprovedManifestSha256"
Write-Output "Release: $ExpectedReleaseId ($($ExpectedReleaseCommit.ToLowerInvariant()))"
