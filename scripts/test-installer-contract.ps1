$ErrorActionPreference='Stop'
$project=[IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
$iss=Get-Content -LiteralPath (Join-Path $project 'installer\PerformanceTracker.iss') -Raw
$builder=Get-Content -LiteralPath (Join-Path $project 'installer\build-installer.ps1') -Raw
$verifier=Get-Content -LiteralPath (Join-Path $project 'scripts\verify-installer-package.ps1') -Raw
$launcher=Get-Content -LiteralPath (Join-Path $project 'scripts\install-verified-package.ps1') -Raw
$packageAcl=Get-Content -LiteralPath (Join-Path $project 'scripts\installer-package-acl.ps1') -Raw
$completion=Get-Content -LiteralPath (Join-Path $project 'installer\assets\complete-installation.ps1') -Raw
$removal=Get-Content -LiteralPath (Join-Path $project 'installer\assets\remove-installation.ps1') -Raw
function Assert-Match([string]$Value,[string]$Pattern,[string]$Message){if($Value-notmatch$Pattern){throw $Message}}
Assert-Match $iss 'PrivilegesRequired=admin' 'Installer must require an approved elevated operator'
Assert-Match $iss 'uninsneveruninstall' 'Installer must retain immutable releases and protected configuration during uninstall'
Assert-Match $iss '\{#ReleaseSource\}\\\.next\\standalone\\\*' 'Installer must package the prepared standalone runtime'
Assert-Match $iss '\{#ReleaseSource\}\\scripts\\\*' 'Installer must package operational helpers'
Assert-Match $iss '\{#NodeRuntimeSource\}\\node\.exe' 'Installer must package the approved portable Node.js executable'
Assert-Match $iss '\{#NodeRuntimeSource\}\\LICENSE' 'Installer must package the Node.js license'
if($iss-match'(?m)^Source: "\{#NodeRuntimeSource\}\\(?:node\.exe|LICENSE)";[^\r\n]*uninsneveruninstall'){throw 'Replaceable Node.js runtime files must be removed during uninstall'}
if($iss-match'Source:\s*"\{#ReleaseSource\}\\\*"'){throw 'Installer must not package the repository root, source tree, caches, or development dependencies'}
Assert-Match $iss 'ExecutionPolicy AllSigned' 'Installer helpers must run under AllSigned policy'
Assert-Match $builder 'Get-AuthenticodeSignature' 'Builder must verify the compiled production installer signature'
Assert-Match $builder 'PerformanceTracker-installer-stage-' 'Production helper signing must use a disposable staging directory'
Assert-Match $builder 'Set-AuthenticodeSignature' 'Builder must sign staged PowerShell helpers'
Assert-Match $builder 'release-integrity\.mjs.+create' 'Builder must recreate integrity metadata after staged helper signing'
Assert-Match $builder 'ReleaseSigningPrivateKey' 'Builder must require the offline release key for the staged manifest'
Assert-Match $builder 'Remove-Item -LiteralPath \$stage -Recurse -Force' 'Builder must remove disposable signing staging data'
Assert-Match $builder '\$productionScriptNames=@\(' 'Builder must define an explicit production-helper allowlist'
$allowlistMatch=[regex]::Match($builder,'(?s)\$productionScriptNames=@\((.*?)\)\s*try')
if(-not$allowlistMatch.Success){throw 'Production-helper allowlist could not be inspected'}
$allowedNames=@([regex]::Matches($allowlistMatch.Groups[1].Value,"'([^']+)'")|ForEach-Object{$_.Groups[1].Value})
if(-not$allowedNames.Count-or@($allowedNames|Sort-Object -Unique).Count-ne$allowedNames.Count){throw 'Production-helper allowlist must be non-empty and contain no duplicates'}
foreach($name in $allowedNames){if(-not(Test-Path -LiteralPath (Join-Path $project "scripts\$name") -PathType Leaf)){throw "Production-helper allowlist names a missing file: $name"}}
foreach($requiredRuntime in @('start-production.ps1','validate-production-env.mjs','release-integrity.mjs','release-signing.mjs','apply-migrations.ps1','backup-production.ps1','scan-evidence-defender.ps1')){
  if($requiredRuntime-notin$allowedNames){throw "Required production helper is absent from the allowlist: $requiredRuntime"}
}
foreach($forbidden in @('lint-progress.mjs','browser-regression.mjs','provision-baseline-local.mjs','release-gate.ps1','test-installer-contract.ps1')){
  if($forbidden-in$allowedNames){throw "Development-only helper is present in the production allowlist: $forbidden"}
}
Assert-Match $builder 'signtool\.exe' 'Builder must Authenticode-sign the production executable'
Assert-Match $builder 'TrustedCompilerSha256' 'Builder must pin the approved installer compiler fingerprint'
Assert-Match $builder "compilerSignature\.Status-ne'Valid'" 'Builder must require a valid compiler Authenticode signature'
Assert-Match $builder 'O=Pyrsys B' 'Builder must restrict the compiler to the approved publisher'
Assert-Match $builder 'compilerSha256=\$compilerSha256' 'Installer build record must identify the compiler fingerprint'
Assert-Match $builder 'performance-tracker-installer-build-v8' 'Builder must bind all production signing-tool identities into portable provenance'
Assert-Match $builder 'FileMode\]::CreateNew' 'Installer provenance must never replace an existing record'
Assert-Match $builder 'Refusing to replace existing installer evidence' 'Builder must preserve existing installer outputs'
Assert-Match $builder 'productionHelperAllowlistSha256' 'Installer provenance must bind the production-helper allowlist'
Assert-Match $builder 'installerSignerThumbprint' 'Installer provenance must bind the Authenticode signer certificate'
Assert-Match $builder 'timestampSignerThumbprint' 'Installer provenance must bind the RFC 3161 timestamp authority'
Assert-Match $builder 'TrustedTimestampCertificateThumbprint' 'Builder must require an independently approved timestamp certificate'
Assert-Match $builder 'TimeStamperCertificate.Thumbprint-ne\$TrustedTimestampCertificateThumbprint' 'Builder must match the actual timestamp authority to independent approval'
Assert-Match $verifier 'ApprovedTimestampCertificateThumbprint' 'Package verifier must require independent timestamp-authority approval'
Assert-Match $verifier 'TimeStamperCertificate.Thumbprint-ne\$ApprovedTimestampCertificateThumbprint' 'Package verifier must enforce the approved timestamp authority'
Assert-Match $verifier 'ApprovedAppVersion' 'Package verifier must require the independently approved release version'
Assert-Match $verifier 'ApprovedInstallerSha256' 'Package verifier must require the independently approved installer fingerprint'
Assert-Match $verifier 'actualInstallerHash-ne\$ApprovedInstallerSha256.ToLowerInvariant' 'Package verifier must reject an installer outside the approved handoff'
Assert-Match $verifier 'record.version-ne\$ApprovedAppVersion' 'Package verifier must reject an unapproved release version'
Assert-Match $verifier 'ApprovedReleaseCommit' 'Package verifier must require the independently approved source commit'
Assert-Match $verifier 'record.releaseCommit-ne\$ApprovedReleaseCommit.ToLowerInvariant' 'Package verifier must reject an unapproved source commit'
Assert-Match $verifier 'ApprovedReleaseId' 'Package verifier must require the independently approved release identifier'
Assert-Match $verifier 'record.releaseId-ne\$ApprovedReleaseId' 'Package verifier must reject an unapproved release identifier'
Assert-Match $verifier 'ApprovedPackageCustodians' 'Package verifier must require explicit handoff custodians'
Assert-Match $packageAcl 'AreAccessRulesProtected' 'Package verifier must require protected handoff ACL inheritance'
Assert-Match $packageAcl 'Installer handoff artifact has an unapproved writer' 'Package verifier must reject unapproved bundle writers'
Assert-Match $verifier 'Assert-ProtectedPackageAcl \$artifactDirectory' 'Package verifier must inspect the installer and signed evidence bundle'
Assert-Match $packageAcl 'Assert-UnchangedInstallerBundle' 'Package verifier must provide a complete bundle stability check'
Assert-Match $verifier 'Assert-UnchangedInstallerBundle \$bundleInitialHashes' 'Package verifier must reject artifacts changed while verification runs'
if($verifier.LastIndexOf('Assert-UnchangedInstallerBundle $bundleInitialHashes')-lt$verifier.IndexOf("& $node (Join-Path $PSScriptRoot 'release-signing.mjs') verify")){throw 'Bundle stability must be checked after cryptographic verification'}
Assert-Match $packageAcl 'FileShare\]::Read' 'Installer bundle lock must deny concurrent writes and replacement'
Assert-Match $launcher 'Invoke-WithLockedInstallerBundle @\(\$installer,\$record,\$signature,\$publicKey,\$node\)' 'Installer launch must lock the signed handoff bundle and external trust inputs'
Assert-Match $launcher 'NodeRuntimeDirectory\)\) ''node\.exe''' 'Installer launch must lock the exact approved runtime executable'
Assert-Match $launcher 'Assert-ProtectedPackageAcl \(\[IO.Path\]::GetDirectoryName\(\$publicKey\)\) @\(\$publicKey\) \$ApprovedPackageCustodians' 'Installer launch must reject unapproved release-key writers'
Assert-Match $launcher 'Assert-ProtectedPackageAcl \(\[IO.Path\]::GetDirectoryName\(\$node\)\) @\(\$node\) \$ApprovedPackageCustodians' 'Installer launch must reject unapproved runtime writers'
Assert-Match $launcher '& \$verifier @verification' 'Installer launch must perform production verification while the bundle is locked'
Assert-Match $launcher 'Start-Process -FilePath \$installer -Wait -PassThru' 'Only the locked verified installer may be launched'
if($launcher.IndexOf('& $verifier @verification')-gt$launcher.IndexOf('Start-Process -FilePath $installer')){throw 'Installer must be verified before launch'}
foreach($approval in @('ApprovedLauncherSha256','ApprovedVerifierSha256','ApprovedAclHelperSha256')){Assert-Match $launcher $approval "Installer launcher must require $approval"}
Assert-Match $launcher 'Get-FileHash -LiteralPath \$tool.Path' 'Installer launcher must fingerprint verification tooling before use'
Assert-Match $launcher '\$toolStreams.Add\(\[IO.File\]::Open\(.+\[IO.FileShare\]::Read\)\)' 'Installer launcher must deny verification-tool writes before fingerprinting'
if($launcher.IndexOf('Get-FileHash -LiteralPath $tool.Path')-gt$launcher.IndexOf('. $aclHelper')){throw 'Verification tooling must be fingerprinted before helper code is loaded'}
if($launcher.IndexOf('$toolStreams.Add')-gt$launcher.IndexOf('Get-FileHash -LiteralPath $tool.Path')){throw 'Verification tooling must be locked before fingerprinting'}
if($launcher.IndexOf('$toolStreams[$index].Dispose()')-lt$launcher.IndexOf('Start-Process -FilePath $installer')){throw 'Verification-tool locks must remain held through installer execution'}
if($launcher.IndexOf('Invoke-WithLockedInstallerBundle @($installer,$record,$signature,$publicKey,$node)')-gt$launcher.IndexOf('& $verifier @verification')){throw 'Package and trust inputs must be locked before cryptographic verification'}
if($launcher.IndexOf('Assert-ProtectedPackageAcl ([IO.Path]::GetDirectoryName($publicKey))')-gt$launcher.IndexOf('& $verifier @verification')){throw 'Release-key ACL must be verified before cryptographic use'}
if($launcher.IndexOf('Assert-ProtectedPackageAcl ([IO.Path]::GetDirectoryName($node))')-gt$launcher.IndexOf('& $verifier @verification')){throw 'Runtime ACL must be verified before execution'}
Assert-Match $builder 'SignerCertificate\.Thumbprint-ne\$SigningCertificateThumbprint' 'Builder must match the compiled EXE to the requested signing certificate'
Assert-Match $builder 'TrustedSignToolSha256' 'Builder must require an independently approved signtool.exe fingerprint'
Assert-Match $builder 'O=Microsoft Corporation' 'Builder must require the Microsoft Authenticode publisher on signtool.exe'
Assert-Match $builder 'signToolSha256=\$signToolSha256' 'Installer provenance must bind the Windows signing-tool fingerprint'
Assert-Match $builder 'recordSignatureFile' 'Production provenance must name its detached signature without a build-machine path'
Assert-Match $builder 'sign \$buildRecordPath' 'Builder must sign the production provenance record'
Assert-Match $builder 'verify \$buildRecordPath \$buildRecordSignaturePath' 'Builder must immediately verify the production provenance signature'
Assert-Match $builder 'release-signing\.mjs.+verify' 'Builder must verify the release signature before compilation'
Assert-Match $builder "standalonePackage.name-ne'performance-tracker'" 'Builder must require the source-controlled application identity'
Assert-Match $builder 'standalonePackage.version-ne\$AppVersion' 'Builder must reject an installer version that differs from the signed release'
if($builder.IndexOf('$standalonePackage.version-ne$AppVersion')-gt$builder.IndexOf('& $CompilerPath @defines')){throw 'Builder must verify the signed release version before compiling the installer'}
Assert-Match $builder 'NodeRuntimeDirectory' 'Builder must require an explicit portable Node.js runtime'
Assert-Match $builder 'nodeRuntimeSha256' 'Installer record must identify the bundled runtime by hash'
Assert-Match $builder 'TrustedNodeRuntimeSha256' 'Builder must pin the approved Node.js runtime fingerprint'
Assert-Match $builder 'runtime fingerprint does not match the approved release runtime' 'Builder must reject an unapproved Node.js binary'
Assert-Match $builder 'O=OpenJS Foundation' 'Builder must require the approved Node.js Authenticode publisher'
Assert-Match $builder 'nodeRuntimeSigner' 'Installer record must identify the Node.js Authenticode publisher'
Assert-Match $verifier "runtimeSignature\.Status-ne'Valid'" 'Package verifier must require a valid Node.js Authenticode signature'
Assert-Match $verifier 'runtimeSignature.SignerCertificate.Subject-ne\$record.nodeRuntimeSigner' 'Package verifier must bind the Node.js publisher to provenance'
if($builder.IndexOf('$nodeExecutable --version')-lt$builder.IndexOf('$nodeRuntimeSha256-ne$TrustedNodeRuntimeSha256.ToLowerInvariant')){throw 'Builder must verify the Node.js fingerprint before executing the runtime'}
if($builder.IndexOf('$nodeExecutable --version')-lt$builder.IndexOf('$nodeRuntimeSignature.Status-ne''Valid''')){throw 'Builder must verify the Node.js publisher before executing the runtime'}
Assert-Match $completion 'TrustedNodeRuntimeSha256' 'Installation completion must pin the bundled runtime hash'
Assert-Match $iss 'TrustedNodeRuntimeSha256' 'Installer completion and repair commands must receive the pinned runtime hash'
Assert-Match $completion 'release-integrity\.mjs.+verify' 'Installed files must be integrity-verified before provisioning'
Assert-Match $completion "runtime\\node\.exe" 'Installation completion must use the bundled Node.js runtime'
Assert-Match $completion 'TrustedPublicKeySha256' 'Installed trust key must be pinned by fingerprint'
Assert-Match $removal 'deliberately retained' 'Uninstall must state its data-retention behavior'
Assert-Match $removal 'IndexOf\(\$root' 'Uninstall must verify each scheduled task belongs to this installation root'
Assert-Match $removal 'Retained \$taskName' 'Uninstall must preserve same-named tasks owned by another installation'
if($iss-match'(?i)(DATABASE_URL|AUTH_JWT_SECRET|MFA_ENCRYPTION_KEY)\s*='){throw 'Installer source must not embed application secrets'}
Write-Output 'Installer security contract tests passed.'
