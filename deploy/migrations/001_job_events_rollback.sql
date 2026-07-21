-- Herald Relay: Rollback for migration 001
-- WARNING: Only use if the migration caused issues AND no data needs to be preserved.

BEGIN;

DROP TABLE IF EXISTS job_events;

ALTER TABLE message_jobs DROP COLUMN IF EXISTS attempt;
ALTER TABLE message_jobs DROP COLUMN IF EXISTS reasoning_effort;

DELETE FROM schema_migrations WHERE version = 1;

COMMIT;
