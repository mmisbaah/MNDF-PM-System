$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'deployment-journal.ps1')
$base=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
$fixture=Join-Path $base ('tracker-journal-test-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture | Out-Null
$journal=$null
try {
  $path=Join-Path $fixture 'operations.jsonl'
  $journal=Open-DeploymentJournal $path
  Write-DeploymentJournal $journal @{format='performance-tracker-deployment-operation-v2';operationId='fixture';status='STARTED'}
  $reader=[IO.FileStream]::new($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
  try {if($reader.Length -eq 0){throw 'Start record was not flushed'}} finally {$reader.Dispose()}
  Write-Output 'PASS start record readable while journal held'
  $rejected=$false
  try {$other=Open-DeploymentJournal $path;$other.Dispose()} catch {$rejected=$true}
  if(-not $rejected){throw 'Concurrent writer accepted'}
  Write-Output 'PASS concurrent journal writer rejected'
  Write-DeploymentJournal $journal @{format='performance-tracker-deployment-operation-v2';operationId='fixture';status='PROMOTED'}
  $journal.Dispose();$journal=$null
  $records=@(Get-Content -LiteralPath $path | ForEach-Object {$_|ConvertFrom-Json})
  if($records.Count -ne 2 -or $records[0].status -ne 'STARTED' -or $records[1].status -ne 'PROMOTED'){throw 'Record sequence corrupted'}
  $journal=Open-DeploymentJournal $path
  Write-DeploymentJournal $journal @{format='performance-tracker-deployment-operation-v2';operationId='second';status='STARTED'}
  $journal.Dispose();$journal=$null
  if(@(Get-Content -LiteralPath $path).Count -ne 3){throw 'Existing records overwritten'}
  Write-Output 'PASS subsequent operations append without overwrite'
  $before=[IO.File]::ReadAllText($path)
  $rejected=$false
  try {$other=Open-DeploymentJournal $path;$other.Dispose()} catch {$rejected=$true}
  if(-not $rejected -or [IO.File]::ReadAllText($path) -ne $before){throw 'Unresolved operation not preserved and blocked'}
  Write-Output 'PASS unresolved start blocks reopening without changing history'
  [IO.File]::AppendAllText($path,'partial')
  $rejected=$false
  try {$other=Open-DeploymentJournal $path;$other.Dispose()} catch {$rejected=$true}
  if(-not $rejected){throw 'Truncated journal accepted'}
  Write-Output 'PASS incomplete final record rejected'
  $rejected=$false
  try {$other=Open-DeploymentJournal (Join-Path $fixture 'missing\operations.jsonl');$other.Dispose()} catch {$rejected=$true}
  if(-not $rejected){throw 'Unavailable journal accepted'}
  Write-Output 'PASS unavailable journal rejected'
  $format='performance-tracker-deployment-operation-v2'
  $start=@{format=$format;operationId='fixture';status='STARTED'}
  $finish=@{format=$format;operationId='fixture';status='PROMOTED'}
  $cases=@(
    @{name='duplicate start';records=@($start,$start)},
    @{name='unmatched terminal';records=@($finish)},
    @{name='duplicate terminal';records=@($start,$finish,$finish)},
    @{name='failed rollback';records=@($start,@{format=$format;operationId='fixture';status='ROLLBACK_FAILED'})},
    @{name='failed cleanup';records=@($start,@{format=$format;operationId='fixture';status='PROMOTED';cleanupFailed=$true})},
    @{name='unknown status';records=@($start,@{format=$format;operationId='fixture';status='UNKNOWN'})}
  )
  foreach($case in $cases){
    $testPath=Join-Path $fixture (([guid]::NewGuid().ToString('N'))+'.jsonl')
    $content=($case.records | ForEach-Object {$_ | ConvertTo-Json -Compress}) -join "`n"
    [IO.File]::WriteAllText($testPath,$content+"`n")
    $rejected=$false
    try {$other=Open-DeploymentJournal $testPath;$other.Dispose()} catch {$rejected=$true}
    if(-not $rejected){throw "Accepted $($case.name)"}
    Write-Output "PASS rejects $($case.name)"
  }
  $legacyPath=Join-Path $fixture 'legacy.jsonl'
  [IO.File]::WriteAllText($legacyPath,(@{format='performance-tracker-deployment-operation-v1';status='PROMOTED'}|ConvertTo-Json -Compress)+"`n")
  $other=Open-DeploymentJournal $legacyPath;$other.Dispose()
  Write-Output 'PASS reads complete legacy journal'
  [IO.File]::AppendAllText($legacyPath,"not-json`n")
  $rejected=$false
  try {$other=Open-DeploymentJournal $legacyPath;$other.Dispose()} catch {$rejected=$true}
  if(-not $rejected){throw 'Malformed JSON accepted'}
  Write-Output 'PASS malformed JSON rejected'
} finally {
  if($journal){$journal.Dispose()}
  if(-not ([IO.Path]::GetFullPath($fixture)).StartsWith("$base\tracker-journal-test-",[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe cleanup path'}
  Remove-Item -LiteralPath $fixture -Recurse -Force
}
