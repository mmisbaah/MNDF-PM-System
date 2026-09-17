$ErrorActionPreference='Stop'
$root=Join-Path ([IO.Path]::GetTempPath()) ('pt-candidate-attestation-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root|Out-Null
$previous=$env:RELEASE_SIGNING_KEY_PASSPHRASE
try{
  $env:RELEASE_SIGNING_KEY_PASSPHRASE='disposable-attestation-test-passphrase'
  $private=Join-Path $root 'private.pem';$public=Join-Path $root 'public.pem'
  & node (Join-Path $PSScriptRoot 'release-signing.mjs') keygen $private $public;if($LASTEXITCODE-ne0){throw 'Disposable key generation failed'}
  $commit='a'*40;$manifest=Join-Path $root 'manifest.json';$gate=Join-Path $root 'gate.json';$branch=Join-Path $root 'branch.json'
  @{format='performance-tracker-release-package-v3';commit=$commit;files=@(@{path='server.js';sha256=('b'*64)});scripts=@(@{path='start-production.ps1';sha256=('c'*64)})}|ConvertTo-Json -Depth 4|Set-Content -LiteralPath $manifest -Encoding utf8
  $now=[DateTimeOffset]::UtcNow.ToString('o')
  @{format='performance-tracker-release-gate-v1';status='PASS';commit=$commit;branch='main';codeOnly=$false;finishedAt=$now;checks=@()}|ConvertTo-Json -Depth 4|Set-Content -LiteralPath $gate -Encoding utf8
  @{format='performance-tracker-release-branch-verification-v1';status='PASS';repository='mmisbaah/MNDF-PM-System';branch='main';verifiedAt=$now}|ConvertTo-Json|Set-Content -LiteralPath $branch -Encoding utf8
  $output=Join-Path $root 'attestation.json';$signature="$output.sig.json"
  & (Join-Path $PSScriptRoot 'new-release-candidate-attestation.ps1') -ReleaseManifestPath $manifest -ReleaseGateResultPath $gate -BranchVerificationResultPath $branch -ReleaseId 'test-release' -Repository 'mmisbaah/MNDF-PM-System' -ReleasePrivateKey $private -ReleasePublicKey $public -OutputPath $output -OutputSignaturePath $signature
  if($LASTEXITCODE-ne0){throw 'Candidate attestation creation failed'}
  & node (Join-Path $PSScriptRoot 'release-signing.mjs') verify $output $signature $public;if($LASTEXITCODE-ne0){throw 'Candidate attestation did not verify'}
  $record=Get-Content -LiteralPath $output -Raw|ConvertFrom-Json
  if($record.format-ne'performance-tracker-release-candidate-attestation-v1'-or$record.releaseCommit-ne$commit-or$record.containsSecrets-ne$false){throw 'Candidate attestation record is incomplete'}
  $badGate=Join-Path $root 'code-only.json';@{format='performance-tracker-release-gate-v1';status='CODE_ONLY_PASS';commit=$commit;branch='main';codeOnly=$true;finishedAt=$now;checks=@()}|ConvertTo-Json -Depth 4|Set-Content -LiteralPath $badGate -Encoding utf8
  $failed=$false;try{& (Join-Path $PSScriptRoot 'new-release-candidate-attestation.ps1') -ReleaseManifestPath $manifest -ReleaseGateResultPath $badGate -BranchVerificationResultPath $branch -ReleaseId 'bad' -Repository 'mmisbaah/MNDF-PM-System' -ReleasePrivateKey $private -ReleasePublicKey $public -OutputPath (Join-Path $root 'bad.json') -OutputSignaturePath (Join-Path $root 'bad.sig.json')}catch{$failed=$_.Exception.Message-match'full PASS'}
  if(-not$failed){throw 'CODE_ONLY_PASS was accepted for a production candidate attestation'}
  Write-Output 'PASS release candidate attestation contract'
}finally{
  if($null-eq$previous){Remove-Item Env:RELEASE_SIGNING_KEY_PASSPHRASE -ErrorAction SilentlyContinue}else{$env:RELEASE_SIGNING_KEY_PASSPHRASE=$previous}
  Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
