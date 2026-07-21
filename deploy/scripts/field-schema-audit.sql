-- Herald Field Schema Audit
-- Run against production Postgres to check what's missing before migration.

SELECT 'message_jobs.attempt' AS check,
       EXISTS (
           SELECT 1 FROM information_schema.columns
           WHERE table_name = 'message_jobs' AND column_name = 'attempt'
       ) AS present;

SELECT 'message_jobs.reasoning_effort' AS check,
       EXISTS (
           SELECT 1 FROM information_schema.columns
           WHERE table_name = 'message_jobs' AND column_name = 'reasoning_effort'
       ) AS present;

SELECT 'job_events table' AS check,
       EXISTS (
           SELECT 1 FROM information_schema.tables
           WHERE table_name = 'job_events'
       ) AS present;

SELECT 'schema_migrations table' AS check,
       EXISTS (
           SELECT 1 FROM information_schema.tables
           WHERE table_name = 'schema_migrations'
       ) AS present;

-- Show current message_jobs columns
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_name = 'message_jobs'
ORDER BY ordinal_position;
