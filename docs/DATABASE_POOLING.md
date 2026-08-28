# Database pooling and resilience

The web process uses a bounded PostgreSQL pool. Pilot defaults are 15 connections, a five-second connection-acquisition timeout, 30-second idle cleanup, 30-minute connection lifetime, 15-second server statement timeout, and 20-second client query timeout. The client timeout is intentionally longer so PostgreSQL cancels expensive work before the application abandons it.

Do not raise `DB_POOL_MAX` merely to hide slow queries. The database administrator must account for every application instance, scheduled worker, backup/export connection, monitoring connection, migration session, and reserved administrative capacity under PostgreSQL `max_connections`. For a single pilot web instance, retain the default until capacity evidence shows a sustained wait queue with acceptable query latency.

The private operations-health endpoint reports allocated, idle, and waiting pool counts. Any waiting request or utilization at or above 90% is a warning. Repeated warnings require query and workload investigation; they do not automatically authorize a larger pool.

Invalid limits or timeout ordering stop application startup. After changing a pool value, rerun configuration validation, the 40-user capacity test, authenticated browser regression, and operations-health check before approval.
