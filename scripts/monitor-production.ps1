param(
  [string]$BaseUrl="http://127.0.0.1:3100",
  [string]$BackupLog="C:\PerformanceTracker\backups\backup-operations.jsonl",
  [string]$AuditExportLog="C:\PerformanceTracker\audit-exports\audit-export-operations.jsonl",
  [string]$AlertDirectory="C:\PerformanceTracker\logs\alerts",
  [string]$ApplicationLogDirectory="C:\PerformanceTracker\logs\application",
  [long]$MaximumApplicationLogBytes=1073741824,
  [int]$MaximumBackupAgeHours=30
)
$ErrorActionPreference="Stop"
if($BaseUrl-notmatch'^http://(127\.0\.0\.1|localhost)(:\d+)?$'){throw "Monitoring must call the application over loopback"}
$secret=$env:OPERATIONS_MONITOR_SECRET;if([string]::IsNullOrWhiteSpace($secret)-or$secret.Length-lt32){throw "OPERATIONS_MONITOR_SECRET is required"}
$alerts=@();$checkedAt=(Get-Date).ToUniversalTime()
try{$health=Invoke-RestMethod -Method Get -Uri "$BaseUrl/api/internal/operations-health" -Headers @{Authorization="Bearer $secret"} -TimeoutSec 30}catch{$health=$null;$alerts+="Application or database health endpoint is unavailable or critical: $($_.Exception.Message)"}
if($health){foreach($check in @($health.checks)){if($check.severity-in@("WARNING","CRITICAL")){$alerts+="$($check.severity): $($check.name) - $($check.message)"}}}
if(-not(Test-Path -LiteralPath $ApplicationLogDirectory)){$alerts+="WARNING: Application log directory is missing"}else{
  $applicationLogs=@(Get-ChildItem -LiteralPath $ApplicationLogDirectory -File -Filter 'application-*.log' -ErrorAction SilentlyContinue)
  if(-not$applicationLogs){$alerts+="WARNING: No application runtime log has been created"}
  $applicationLogBytes=($applicationLogs|Measure-Object -Property Length -Sum).Sum
  if($applicationLogBytes-gt$MaximumApplicationLogBytes){$alerts+="WARNING: Preserved application logs exceed $MaximumApplicationLogBytes bytes; apply only the approved SECURITY_TELEMETRY retention procedure"}
}
if(-not(Test-Path -LiteralPath $BackupLog)){$alerts+="CRITICAL: No backup operations log found"}else{
  $lastLine=Get-Content -LiteralPath $BackupLog -Tail 1;$last=$lastLine|ConvertFrom-Json;$lastTime=if($last.verifiedAt){[datetime]$last.verifiedAt}elseif($last.failedAt){[datetime]$last.failedAt}else{[datetime]::MinValue};$age=$checkedAt-$lastTime.ToUniversalTime()
  if($last.status-ne"SUCCESS"){$alerts+="CRITICAL: Most recent backup operation failed"};if($age.TotalHours-gt$MaximumBackupAgeHours){$alerts+="CRITICAL: Last verified backup is $([math]::Round($age.TotalHours,1)) hours old"}
}
if(-not(Test-Path -LiteralPath $AuditExportLog)){$alerts+="CRITICAL: No audit export operations log found"}else{$lastAudit=Get-Content -LiteralPath $AuditExportLog -Tail 1|ConvertFrom-Json;$auditTime=if($lastAudit.verifiedAt){[datetime]$lastAudit.verifiedAt}elseif($lastAudit.failedAt){[datetime]$lastAudit.failedAt}else{[datetime]::MinValue};$auditAge=$checkedAt-$auditTime.ToUniversalTime();if($lastAudit.status-ne"SUCCESS"){$alerts+="CRITICAL: Most recent audit export failed"};if($auditAge.TotalHours-gt30){$alerts+="CRITICAL: Last verified audit export is $([math]::Round($auditAge.TotalHours,1)) hours old"}}
foreach($taskName in @("Performance-Tracker-Scheduled-Jobs","Performance-Tracker-Evidence-Scanner","Performance-Tracker-Daily-Backup","Performance-Tracker-Audit-Export")){
  $task=Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue;$info=if($task){$task|Get-ScheduledTaskInfo}else{$null};if(-not$task){$alerts+="CRITICAL: Scheduled task missing: $taskName"}elseif($task.State-eq"Disabled"){$alerts+="CRITICAL: Scheduled task disabled: $taskName"}elseif($info.LastTaskResult-ne0-and$info.LastRunTime-gt[datetime]::MinValue){$alerts+="WARNING: $taskName last result was $($info.LastTaskResult)"}
}
New-Item -ItemType Directory -Force -Path $AlertDirectory|Out-Null;$result=[ordered]@{status=if($alerts.Count){"ATTENTION_REQUIRED"}else{"HEALTHY"};checkedAt=$checkedAt.ToString("o");alerts=$alerts};$line=$result|ConvertTo-Json -Depth 4 -Compress;Add-Content -LiteralPath (Join-Path $AlertDirectory "monitor-history.jsonl") -Value $line -Encoding utf8
if($alerts.Count){$incident=Join-Path $AlertDirectory "incident-$($checkedAt.ToString('yyyyMMddTHHmmssZ')).json";$result|ConvertTo-Json -Depth 4|Set-Content -LiteralPath $incident -Encoding utf8;Write-Error ($alerts-join[Environment]::NewLine)}else{Write-Output $line}
