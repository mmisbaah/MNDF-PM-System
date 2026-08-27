# In-app notifications and scheduled jobs

The pilot notification channel is the authenticated Performance Tracker PWA. No official email address, SMS provider, or third-party messaging service is required. Deadline and correction notices appear in the notification center; users may opt into generic device alerts. Device alerts contain no appraisal, complaint, score, or personnel details.

`run-scheduled-jobs.ps1` calls the loopback-only scheduler every minute. Grievance deadlines run approximately every minute, cycle synchronization every 15 minutes, and recommendation eligibility every hour. Each execution is stored in `scheduled_job_runs`, including result or failure. The reverse proxy blocks all `/api/internal/*` routes.

Install the worker with `install-scheduled-jobs-task.ps1` under the dedicated service account. Monitor failed task executions and database rows where `succeeded=false`. If the worker is unavailable, complaint records remain open; the next successful run marks overdue cases and releases queued notifications using server timestamps.
