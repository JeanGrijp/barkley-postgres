BEGIN;

CREATE TABLE lane (
    id BIGINT PRIMARY KEY,
    tenant_id BIGINT NOT NULL REFERENCES tenant (id) ON DELETE CASCADE,
    code TEXT NOT NULL,
    name TEXT NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, code)
);

CREATE INDEX idx_lane_tenant ON lane (tenant_id);

CREATE TRIGGER trg_lane_updated_at
BEFORE UPDATE ON lane
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

ALTER TABLE ticket ADD COLUMN lane_id BIGINT;

-- create a default lane per tenant so existing data is preserved
INSERT INTO lane (id, tenant_id, code, name, description)
SELECT tenant_id * 1000 + 1, tenant_id, 'default', 'Default Lane', 'Auto-created during lane migration'
FROM tenant
ON CONFLICT (tenant_id, code) DO NOTHING;

UPDATE ticket AS t
SET lane_id = l.id
FROM lane AS l
WHERE l.tenant_id = t.tenant_id AND l.code = 'default';

ALTER TABLE ticket
    ALTER COLUMN lane_id SET NOT NULL;

ALTER TABLE ticket
    ADD CONSTRAINT ticket_lane_fk FOREIGN KEY (tenant_id, lane_id)
        REFERENCES lane (tenant_id, id) ON DELETE RESTRICT;

-- refresh queue indexes to include lane partition
DROP INDEX IF EXISTS idx_ticket_queue;
CREATE INDEX idx_ticket_queue ON ticket (
    tenant_id,
    lane_id,
    status,
    position ASC,
    created_at ASC,
    id ASC
);

CREATE INDEX IF NOT EXISTS idx_ticket_lane ON ticket (tenant_id, lane_id);

COMMIT;
