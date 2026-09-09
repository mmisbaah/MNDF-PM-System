$ErrorActionPreference='Stop'
$testRoot=Join-Path ([IO.Path]::GetTempPath()) ('pt-installer-launcher-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot|Out-Null
foreach($name in @('install-verified-package.ps1','verify-installer-package.ps1','installer-package-acl.ps1','release-signing.mjs')){Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination $testRoot}
$launcher=Join-Path $testRoot 'install-verified-package.ps1'
$verifier=Join-Path $testRoot 'verify-installer-package.ps1'
$aclHelper=Join-Path $testRoot 'installer-package-acl.ps1'
$releaseSigningHelper=Join-Path $testRoot 'release-signing.mjs'
try{
$launcherHash=(Get-FileHash -LiteralPath $launcher -Algorithm SHA256).Hash
$verifierHash=(Get-FileHash -LiteralPath $verifier -Algorithm SHA256).Hash
$helperHash=(Get-FileHash -LiteralPath $aclHelper -Algorithm SHA256).Hash
$signingHelperHash=(Get-FileHash -LiteralPath $releaseSigningHelper -Algorithm SHA256).Hash
$common=@{
  InstallerPath='missing.exe';BuildRecordPath='missing.json';ReleasePublicKey='missing.pem';NodeRuntimeDirectory='missing-runtime'
  ApprovedInstallerSha256=('1'*64);ApprovedSigningCertificateThumbprint=('2'*40);ApprovedTimestampCertificateThumbprint=('3'*40)
  ApprovedAppVersion='1.0.0';ApprovedReleaseCommit=('4'*40);ApprovedReleaseId='release-1';ApprovedSignToolSha256=('5'*64)
  ApprovedReleasePublicKeySha256=('6'*64);ApprovedPackageCustodians=@('S-1-5-18')
}
$failed=$false;try{& $launcher @common -ApprovedLauncherSha256 ('0'*64) -ApprovedVerifierSha256 $verifierHash -ApprovedAclHelperSha256 $helperHash -ApprovedReleaseSigningHelperSha256 $signingHelperHash}catch{$failed=$_.Exception.Message-match'launcher fingerprint'}
if(-not$failed){throw 'Installer launcher accepted an unapproved self fingerprint'}
$failed=$false;try{& $launcher @common -ApprovedLauncherSha256 $launcherHash -ApprovedVerifierSha256 ('0'*64) -ApprovedAclHelperSha256 $helperHash -ApprovedReleaseSigningHelperSha256 $signingHelperHash}catch{$failed=$_.Exception.Message-match'verifier fingerprint'}
if(-not$failed){throw 'Installer launcher accepted an unapproved verifier fingerprint'}
$failed=$false;try{& $launcher @common -ApprovedLauncherSha256 $launcherHash -ApprovedVerifierSha256 $verifierHash -ApprovedAclHelperSha256 ('0'*64) -ApprovedReleaseSigningHelperSha256 $signingHelperHash}catch{$failed=$_.Exception.Message-match'ACL helper fingerprint'}
if(-not$failed){throw 'Installer launcher accepted an unapproved ACL helper fingerprint'}
$failed=$false;try{& $launcher @common -ApprovedLauncherSha256 $launcherHash -ApprovedVerifierSha256 $verifierHash -ApprovedAclHelperSha256 $helperHash -ApprovedReleaseSigningHelperSha256 ('0'*64)}catch{$failed=$_.Exception.Message-match'release-signing helper fingerprint'}
if(-not$failed){throw 'Installer launcher accepted an unapproved release-signing helper fingerprint'}
$failed=$false;try{& $launcher @common -ApprovedLauncherSha256 $launcherHash -ApprovedVerifierSha256 $verifierHash -ApprovedAclHelperSha256 $helperHash -ApprovedReleaseSigningHelperSha256 $signingHelperHash}catch{$failed=$true}
if(-not$failed){throw 'Approved verification tools did not reach fail-closed bundle validation'}
foreach($tool in @($launcher,$verifier,$aclHelper,$releaseSigningHelper)){
  $released=[IO.File]::Open($tool,[IO.FileMode]::Open,[IO.FileAccess]::Write,[IO.FileShare]::ReadWrite)
  $released.Dispose()
}
Write-Output 'Installer launcher integrity tests passed.'
}finally{Remove-Item -LiteralPath $testRoot -Recurse -Force}
