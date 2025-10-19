-- 002_worker_contact_tenant_slug.sql
-- Add slug to tenant and contact/address fields to worker
BEGIN;

-- Tenant slug (derive initial values from name)
ALTER TABLE tenant ADD COLUMN IF NOT EXISTS slug TEXT;

UPDATE tenant
SET
    slug = lower(
        regexp_replace(name, '[^a-z0-9]+', '-', 'g')
    )
WHERE
    slug IS NULL;
-- Trim leading/trailing '-'
UPDATE tenant
SET
    slug = regexp_replace(
        regexp_replace(slug, '^-+', ''),
        '-+$',
        ''
    );
-- Fallback if empty
UPDATE tenant SET slug = 'tenant' || id::text WHERE (slug IS NULL OR slug = '');

ALTER TABLE tenant ALTER COLUMN slug SET NOT NULL;

DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND indexname = 'idx_tenant_slug'
    ) THEN
        CREATE UNIQUE INDEX idx_tenant_slug ON tenant (slug);
    END IF;
END $$;

-- Worker contact/address fields (nullable)
ALTER TABLE worker ADD COLUMN IF NOT EXISTS document TEXT;

ALTER TABLE worker ADD COLUMN IF NOT EXISTS phone TEXT;

ALTER TABLE worker ADD COLUMN IF NOT EXISTS address_street TEXT;

ALTER TABLE worker ADD COLUMN IF NOT EXISTS address_number TEXT;

ALTER TABLE worker ADD COLUMN IF NOT EXISTS address_complement TEXT;

ALTER TABLE worker
ADD COLUMN IF NOT EXISTS address_neighborhood TEXT;

ALTER TABLE worker ADD COLUMN IF NOT EXISTS address_city TEXT;

ALTER TABLE worker ADD COLUMN IF NOT EXISTS address_state TEXT;

ALTER TABLE worker ADD COLUMN IF NOT EXISTS address_zip TEXT;

ALTER TABLE worker ADD COLUMN IF NOT EXISTS address_country TEXT;

COMMIT;