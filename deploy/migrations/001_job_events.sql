-- Herald Relay: Job Events durable streaming schema
-- Run against production Postgres BEFORE deploying new relay code.
-- Idempotent: uses IF NOT EXISTS throughout.

BEGIN;

-- Schema version tracking
CREATE TABLE IF NOT EXISTS schema_migrations (
    version     INTEGER PRIMARY KEY,
    name        TEXT NOT NULL,
    applied_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Skip if already applied
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM schema_migrations WHERE version = 1) THEN
        RAISE NOTICE 'Migration 001 already applied, skipping';
        RETURN;
    END IF;

    -- message_jobs.attempt
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'message_jobs' AND column_name = 'attempt'
    ) THEN
        ALTER TABLE message_jobs ADD COLUMN attempt INTEGER NOT NULL DEFAULT 0;
    END IF;

    -- message_jobs.reasoning_effort
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'message_jobs' AND column_name = 'reasoning_effort'
    ) THEN
        ALTER TABLE message_jobs ADD COLUMN reasoning_effort TEXT;
    END IF;

    -- job_events table
    CREATE TABLE IF NOT EXISTS job_events (
        id            TEXT PRIMARY KEY,
        job_id        TEXT NOT NULL REFERENCES message_jobs(id),
        seq           BIGINT NOT NULL,
        attempt       INTEGER NOT NULL,
        source_seq    BIGINT,  -- NULL for relay-generated terminal events
        type          TEXT NOT NULL,
        payload_json  JSONB NOT NULL,
        created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
    );

    -- Unique index: one seq per job
    CREATE UNIQUE INDEX IF NOT EXISTS ux_job_events_job_seq
        ON job_events(job_id, seq);

    -- Idempotency index: deduplicate connector events (source_seq NOT NULL)
    -- Relay-generated terminal events have source_seq=NULL and use append_job_event's
    -- own dedup logic (checks job terminal status + attempt mismatch).
    CREATE UNIQUE INDEX IF NOT EXISTS ux_job_events_job_attempt_src
        ON job_events(job_id, attempt, source_seq)
        WHERE source_seq IS NOT NULL;

    -- Lookup index: SSE replay after cursor
    CREATE INDEX IF NOT EXISTS ix_job_events_job_seq
        ON job_events(job_id, seq);

    -- Record migration
    INSERT INTO schema_migrations (version, name) VALUES (1, '001_job_events');

    RAISE NOTICE 'Migration 001 applied successfully';
END $$;

COMMIT;
