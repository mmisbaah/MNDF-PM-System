param([string]$BaseUrl="http://127.0.0.1:3100")
$ErrorActionPreference="Stop"
if($BaseUrl-notmatch'^http://(127\.0\.0\.1|localhost)(:\d+)?$'){throw"Scheduled jobs must call the application over loopback"}
$secret=$env:GRIEVANCE_CRON_SECRET
if([string]::IsNullOrWhiteSpace($secret)-or$secret.Length-lt32){throw"GRIEVANCE_CRON_SECRET is required"}
$response=Invoke-RestMethod -Method Post -Uri "$BaseUrl/api/internal/scheduled-jobs" -Headers @{Authorization="Bearer $secret"} -ContentType "application/json" -Body '{}' -TimeoutSec 120
if(-not$response.success){throw"One or more scheduled jobs failed"}
Write-Host "Scheduled jobs completed: $(@($response.runs).Count) job(s) executed"
