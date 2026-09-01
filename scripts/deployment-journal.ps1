function Assert-DeploymentJournalHistory($Stream) {
  $Stream.Seek(0,[IO.SeekOrigin]::Begin) | Out-Null
  $reader=[IO.StreamReader]::new($Stream,[Text.UTF8Encoding]::new($false,$true),$true,4096,$true)
  $operations=@{}
  $terminal=@('FAILED','INITIALIZED','PROMOTED','ROLLED_BACK','ROLLBACK_FAILED')
  $lineNumber=0
  try {
    while($null -ne ($line=$reader.ReadLine())){
      $lineNumber++
      try {$record=ConvertFrom-Json -InputObject $line -ErrorAction Stop} catch {throw "Invalid deployment journal JSON at line $lineNumber; custodian review required"}
      if($record.format -eq 'performance-tracker-deployment-operation-v1'){
        if($record.status -notin $terminal){throw "Invalid legacy deployment status at line $lineNumber"}
        if($record.status -eq 'ROLLBACK_FAILED'){throw 'Prior rollback failed; attended reconciliation required'}
        continue
      }
      if($record.format -ne 'performance-tracker-deployment-operation-v2' -or [string]::IsNullOrWhiteSpace($record.operationId)){throw "Invalid deployment record at line $lineNumber"}
      $id=[string]$record.operationId
      if($record.status -eq 'STARTED'){
        if($operations.ContainsKey($id)){throw 'Duplicate deployment start; custodian review required'}
        if(@($operations.Values | Where-Object {$_ -eq 'STARTED'}).Count){throw 'Overlapping unresolved deployments; custodian review required'}
        $operations[$id]='STARTED'
      } elseif($record.status -in $terminal){
        if(-not $operations.ContainsKey($id) -or $operations[$id] -ne 'STARTED'){throw 'Unmatched or duplicate deployment completion; custodian review required'}
        if($record.status -eq 'ROLLBACK_FAILED' -or $record.cleanupFailed -eq $true){throw 'Prior rollback or cleanup failed; attended reconciliation required'}
        $operations[$id]=[string]$record.status
      } else {throw "Unknown deployment status at line $lineNumber"}
    }
    if(@($operations.Values | Where-Object {$_ -eq 'STARTED'}).Count){throw 'Unresolved deployment start; inspect CurrentLink, task and health before reconciliation'}
  } finally {$reader.Dispose()}
}

function Open-DeploymentJournal([string]$Path) {
  # Deny other writers while this deployment owns the journal; readers may inspect it.
  $stream=[IO.FileStream]::new($Path,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::Read)
  try {
    if($stream.Length -gt 0){
      $stream.Seek(-1,[IO.SeekOrigin]::End) | Out-Null
      if($stream.ReadByte() -ne 10){throw 'Deployment journal has an incomplete last record; custodian review required'}
    }
    Assert-DeploymentJournalHistory $stream
    $stream.Seek(0,[IO.SeekOrigin]::End) | Out-Null
    return $stream
  } catch {$stream.Dispose();throw}
}

function Write-DeploymentJournal($Stream, $Entry) {
  $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($Entry | ConvertTo-Json -Compress -Depth 6)+"`n")
  $Stream.Write($bytes,0,$bytes.Length)
  $Stream.Flush($true)
}
