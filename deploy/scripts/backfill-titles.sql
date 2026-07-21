-- Herald Title Backfill
-- Derives titles from first user message for conversations still using default placeholders.
-- Idempotent: only updates rows whose title is still the expected placeholder.
--
-- Usage:
--   1. Dry run:  psql -f backfill-titles.sql -v DRY_RUN=true
--   2. Execute:  psql -f backfill-titles.sql -v DRY_RUN=false

\set ON_ERROR_STOP on

-- Default to dry run if not specified
SELECT COALESCE(:'DRY_RUN', 'true') AS dry_run \gset

BEGIN;

-- Show what would change (dry run) or apply changes
DO $$
DECLARE
    rec RECORD;
    derived TEXT;
    dry_run BOOLEAN := current_setting('app.dry_run', true)::BOOLEAN;
    updated_count INTEGER := 0;
BEGIN
    -- Default to dry run
    IF dry_run IS NULL THEN dry_run := TRUE; END IF;

    FOR rec IN
        SELECT c.id, c.title, m.text AS first_message_text
        FROM conversations c
        JOIN LATERAL (
            SELECT text FROM messages
            WHERE conversation_id = c.id AND role = 'user'
            ORDER BY created_at ASC
            LIMIT 1
        ) m ON TRUE
        WHERE c.title IN ('Herald', 'New Chat')
        ORDER BY c.created_at DESC
    LOOP
        -- Derive title: collapse whitespace, truncate at 40 chars
        derived := TRIM(BOTH ' ' FROM regexp_replace(rec.first_message_text, '\s+', ' ', 'g'));
        IF LENGTH(derived) > 40 THEN
            derived := LEFT(derived, 37) || '...';
        END IF;

        IF dry_run THEN
            RAISE NOTICE 'DRY RUN: % "%" -> "%"', rec.id, rec.title, derived;
        ELSE
            UPDATE conversations SET title = derived, updated_at = NOW()
            WHERE id = rec.id AND title IN ('Herald', 'New Chat');
            updated_count := updated_count + 1;
        END IF;
    END LOOP;

    IF dry_run THEN
        RAISE NOTICE 'DRY RUN complete. No changes made.';
    ELSE
        RAISE NOTICE 'Backfill complete. Updated % conversations.', updated_count;
    END IF;
END $$;

-- Commit only if not dry run
SELECT CASE WHEN :'DRY_RUN' = 'false' THEN 'COMMIT' ELSE 'ROLLBACK' END AS action \gexec
