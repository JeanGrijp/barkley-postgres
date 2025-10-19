-- Extend enum ticket_event_type with new values if they do not exist yet.
-- Safe to run multiple times.

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_type t
    JOIN pg_enum e ON e.enumtypid = t.oid
    WHERE t.typname = 'ticket_event_type' AND e.enumlabel = 'cancelled'
  ) THEN
    ALTER TYPE ticket_event_type ADD VALUE 'cancelled';
  END IF;
END$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_type t
    JOIN pg_enum e ON e.enumtypid = t.oid
    WHERE t.typname = 'ticket_event_type' AND e.enumlabel = 'priority_changed'
  ) THEN
    ALTER TYPE ticket_event_type ADD VALUE 'priority_changed';
  END IF;
END$$;

