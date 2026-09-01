# Deployment-operation journal

Promotion opens its journal and flushes a version 2 `STARTED` record before
initializing or switching a release, or stopping the task. Failure to open/write
that record aborts before these changes. The journal handle denies competing
writers until completion. This serializes users of the same journal, not
deployments configured with different journal paths: use one protected canonical
journal per installation.

Start and terminal records share `operationId`. Terminal records include the
actual completion time, previous target and a cleanup-failure flag. Cleanup
failure does not skip the attempt to record the result. If the terminal write
fails, the command reports the deployment state and operation ID and fails;
it does not claim the journal completed or blindly switch releases again.

Before retrying an interrupted operation, inspect the current junction, scheduled
task and health, and correlate its start record with a terminal record. A start
without a terminal record now blocks reopening the journal. Failed rollback or
cleanup also blocks further deployment. Duplicate starts/completions, unmatched
completions, overlapping starts, unknown formats/statuses and malformed JSON are
rejected during history validation under the writer lock. An incomplete final line is rejected
and preserved for custodian review instead of appending into it. Older complete
version 1 records remain readable alongside new records.

There is no automatic recovery or bypass flag. If blocked, stop release attempts,
preserve a custody copy of the original journal, and have the deployment operator
and System Authorizer review the current target, service health and release
identity. Record the actual outcome and an approved recovery plan in the incident
record before any journal repair or replacement. Do not fabricate a successful
terminal record merely to pass this gate. A dedicated audited reconciliation
command is not implemented by this change; recovery remains attended.

The local JSONL file is **not immutable or tamper-evident**. Protect it with ACLs
and include it in approved off-host operational evidence retention. Flush requests
durability from the OS; it cannot guarantee survival of hardware/controller
failure. Keep its parent directory protected against replacement and use local
storage; network-share locking semantics require separate verification.

Run `scripts/test-deployment-journal.ps1` for disposable-file tests covering flush,
writer exclusion, append preservation, unresolved starts, failed rollback/cleanup,
invalid sequences, legacy records, malformed/truncated records and unavailable paths.
These tests do not exercise actual release switching or simulate full-disk/power
loss. The attended Windows promotion/rollback rehearsal remains required.
