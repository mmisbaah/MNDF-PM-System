param(
  [Parameter(Mandatory=$true)][string]$BundleDirectory,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ApprovedBundleManifestSha256,
  [Parameter(Mandatory=$true)][string]$TrustedNodeExecutable,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ApprovedNodeSha256,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ApprovedVerifierSha256,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ApprovedSigningHelperSha256,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ApprovedIntegrityHelperSha256
)
$ErrorActionPreference='Stop'
function Get-Sha256([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Assert-ExactFields($Object,[string[]]$Expected,[string]$Name){
  $actual=@($Object.PSObject.Properties.Name|Sort-Object)-join','
  if($actual-ne(@($Expected|Sort-Object)-join',')){throw "$Name schema is incomplete or contains unknown fields"}
}
function Assert-OrdinaryPath([string]$Path,[string]$Boundary){
  $current=Get-Item -LiteralPath $Path -Force
  while($current){
    if(($current.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw "Bundle path contains a junction or symbolic link: $($current.FullName)"}
    if($current.FullName-eq$Boundary){break}
    $parent=[IO.Path]::GetDirectoryName($current.FullName)
    if([string]::IsNullOrWhiteSpace($parent)-or$parent-eq$current.FullName){throw 'Bundle path escaped its verification boundary'}
    $current=Get-Item -LiteralPath $parent -Force
  }
}
$bundle=[IO.Path]::GetFullPath($BundleDirectory).TrimEnd('\')
$node=[IO.Path]::GetFullPath($TrustedNodeExecutable)
$verifier=[IO.Path]::GetFullPath($MyInvocation.MyCommand.Path)
$signingHelper=Join-Path $PSScriptRoot 'release-signing.mjs'
$integrityHelper=Join-Path $PSScriptRoot 'release-integrity.mjs'
if(-not(Test-Path -LiteralPath $bundle -PathType Container)){throw 'Staging rehearsal bundle was not found'}
$manifestPath=Join-Path $bundle 'bundle-manifest.json'
if(-not(Test-Path -LiteralPath $manifestPath -PathType Leaf)){throw 'Bundle manifest was not found'}
$trustItems=@(
  @{path=$node;hash=$ApprovedNodeSha256;name='Node runtime'},
  @{path=$verifier;hash=$ApprovedVerifierSha256;name='bundle verifier'},
  @{path=$signingHelper;hash=$ApprovedSigningHelperSha256;name='release-signing helper'},
  @{path=$integrityHelper;hash=$ApprovedIntegrityHelperSha256;name='release-integrity helper'}
)
foreach($item in $trustItems){
  if(-not(Test-Path -LiteralPath $item.path -PathType Leaf)){throw "$($item.name) was not found"}
}
$trustStreams=[Collections.Generic.List[IO.FileStream]]::new()
foreach($path in @($node,$verifier,$signingHelper,$integrityHelper,$manifestPath)){$trustStreams.Add([IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read))}
try {
foreach($item in $trustItems){if((Get-Sha256 $item.path)-ne$item.hash.ToLowerInvariant()){throw "$($item.name) fingerprint does not match independent approval"}}
$nodeSignature=Get-AuthenticodeSignature -LiteralPath $node
if($nodeSignature.Status-ne'Valid'-or$nodeSignature.SignerCertificate.Subject-notmatch'O=OpenJS Foundation'){throw 'Trusted Node runtime must have a valid OpenJS Foundation Authenticode signature'}
Assert-OrdinaryPath $bundle $bundle
if((Get-Sha256 $manifestPath)-ne$ApprovedBundleManifestSha256.ToLowerInvariant()){throw 'Bundle manifest fingerprint does not match independent approval'}
$manifest=Get-Content -LiteralPath $manifestPath -Raw|ConvertFrom-Json
Assert-ExactFields $manifest @('format','rehearsalOnly','createdAt','publicKeySha256','releases','files') 'Bundle manifest'
if($manifest.format-ne'performance-tracker-staging-rehearsal-bundle-v1'-or$manifest.rehearsalOnly-ne$true){throw 'Bundle is not an approved rehearsal-only format'}
if($manifest.publicKeySha256-notmatch'^[0-9a-f]{64}$'){throw 'Bundle public-key fingerprint is invalid'}
$created=[datetime]$manifest.createdAt
if($created.Kind-ne[DateTimeKind]::Utc-or$created.ToUniversalTime()-gt(Get-Date).ToUniversalTime().AddMinutes(5)){throw 'Bundle creation timestamp is invalid'}
if(-not$manifest.files-or$manifest.files.Count-eq0){throw 'Bundle inventory is empty'}
$expected=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
foreach($file in $manifest.files){
  Assert-ExactFields $file @('path','sha256') 'Bundle file entry'
  $unsafeParts=@($file.path.Split('/')|Where-Object{$_-in@('','.', '..')})
  if($file.path-notmatch'^[A-Za-z0-9._/-]+$'-or$file.path.StartsWith('/')-or$unsafeParts.Count){throw 'Bundle inventory contains an unsafe path'}
  if($file.sha256-notmatch'^[0-9a-f]{64}$'-or$expected.ContainsKey([string]$file.path)){throw 'Bundle inventory contains an invalid or duplicate entry'}
  $expected.Add([string]$file.path,[string]$file.sha256)
}
$actualFiles=@(Get-ChildItem -LiteralPath $bundle -File -Force -Recurse|Where-Object{$_.FullName-ne$manifestPath}|Sort-Object FullName)
if($actualFiles.Count-ne$expected.Count){throw 'Bundle file set differs from the approved inventory'}
$streams=[Collections.Generic.List[IO.FileStream]]::new()
try {
  foreach($file in $actualFiles){
    Assert-OrdinaryPath $file.FullName $bundle
    $relative=$file.FullName.Substring($bundle.Length+1).Replace('\','/')
    if(-not$expected.ContainsKey($relative)){throw "Unapproved bundle file found: $relative"}
    $streams.Add([IO.File]::Open($file.FullName,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read))
  }
  foreach($file in $actualFiles){
    $relative=$file.FullName.Substring($bundle.Length+1).Replace('\','/')
    if((Get-Sha256 $file.FullName)-ne$expected[$relative]){throw "Bundle file fingerprint changed: $relative"}
  }
  $publicKey=Join-Path $bundle 'trust\rehearsal-release-public.pem'
  if((Get-Sha256 $publicKey)-ne$manifest.publicKeySha256){throw 'Bundled release public key fingerprint does not match the manifest'}
  Assert-ExactFields $manifest.releases @('baseline','candidate','failure') 'Bundle release roles'
  foreach($role in @('baseline','candidate','failure')){
    $record=$manifest.releases.$role
    Assert-ExactFields $record @('commit','manifestSha256','signatureSha256','rehearsalOnly') "$role release record"
    if($record.commit-notmatch'^[0-9a-f]{40}$'-or$record.manifestSha256-notmatch'^[0-9a-f]{64}$'-or$record.signatureSha256-notmatch'^[0-9a-f]{64}$'){throw "$role release record contains invalid fingerprints"}
    $release=Join-Path $bundle "releases\$role";$standalone=Join-Path $release '.next\standalone'
    $releaseManifest=Join-Path $standalone 'release-manifest.json';$releaseSignature=Join-Path $standalone 'release-manifest.sig.json'
    if((Get-Sha256 $releaseManifest)-ne$record.manifestSha256-or(Get-Sha256 $releaseSignature)-ne$record.signatureSha256){throw "$role release evidence does not match the bundle manifest"}
    $marker=Test-Path -LiteralPath (Join-Path $standalone 'rehearsal-only.json') -PathType Leaf
    if($role-eq'failure'-and($record.rehearsalOnly-ne$true-or-not$marker)){throw 'Failure release is not marked rehearsal-only'}
    if($role-ne'failure'-and($record.rehearsalOnly-ne$false-or$marker)){throw "$role release cannot be marked rehearsal-only"}
    & $node $signingHelper verify $releaseManifest $releaseSignature $publicKey
    if($LASTEXITCODE-ne0){throw "$role release signature verification failed"}
    & $node $integrityHelper verify $standalone (Join-Path $release 'scripts')
    if($LASTEXITCODE-ne0){throw "$role release integrity verification failed"}
  }
} finally {
  for($index=$streams.Count-1;$index-ge0;$index--){$streams[$index].Dispose()}
}
Write-Output "Staging rehearsal bundle verification passed: $($ApprovedBundleManifestSha256.ToLowerInvariant())"
} finally {
  for($index=$trustStreams.Count-1;$index-ge0;$index--){$trustStreams[$index].Dispose()}
}
