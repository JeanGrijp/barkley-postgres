-- =========================================================
-- Barkley DB Schema (PostgreSQL) - IDs BIGINT (Snowflake)
-- =========================================================

-- 1) Tipos ENUM para consistência semântica
CREATE TYPE ticket_status AS ENUM ('waiting', 'working', 'finished', 'cancelled');

CREATE TYPE ticket_priority AS ENUM ('low', 'normal', 'high', 'urgent');

CREATE TYPE ticket_event_type AS ENUM (
  'created',
  'assigned',
  'started',
  'finished',
  'requeued',
  'cancelled',
  'priority_changed',
  'note'
);

-- 2) Função e trigger para updated_at = now() em UPDATE
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS trigger AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- =========================================================
-- TENANT
-- =========================================================

-- Entidade de tenant/organização. Workers, owners, pets, etc. pertencem a um tenant.
CREATE TABLE tenant (
    id BIGINT PRIMARY KEY,
    name TEXT NOT NULL,
    slug TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX idx_tenant_name ON tenant (name);

CREATE UNIQUE INDEX idx_tenant_slug ON tenant (slug);

CREATE TRIGGER trg_tenant_updated_at
BEFORE UPDATE ON tenant
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- =========================================================
-- TABELAS PRINCIPAIS
-- =========================================================

-- OWNER
CREATE TABLE owner (
    id BIGINT PRIMARY KEY,
    tenant_id BIGINT NOT NULL REFERENCES tenant (id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    document TEXT NOT NULL,
    phone TEXT,
    email TEXT,
    address_street TEXT,
    address_number TEXT,
    address_complement TEXT,
    address_neighborhood TEXT,
    address_city TEXT,
    address_state TEXT,
    address_zip TEXT,
    address_country TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- Permite FKs (tenant_id, owner_id) sem tornar PK composto
    UNIQUE (tenant_id, id),
    -- Documentos únicos por tenant
    UNIQUE (tenant_id, document)
);

CREATE INDEX idx_owner_document ON owner (tenant_id, document);

CREATE INDEX idx_owner_phone ON owner (tenant_id, phone);

CREATE INDEX idx_owner_email ON owner (tenant_id, email);

CREATE INDEX idx_owner_name ON owner (tenant_id, name);

CREATE TRIGGER trg_owner_updated_at
BEFORE UPDATE ON owner
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- WORKER
CREATE TABLE worker (
    id BIGINT PRIMARY KEY,
    tenant_id BIGINT NOT NULL REFERENCES tenant (id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    email TEXT NOT NULL,
    document TEXT,
    phone TEXT,
    address_street TEXT,
    address_number TEXT,
    address_complement TEXT,
    address_neighborhood TEXT,
    address_city TEXT,
    address_state TEXT,
    address_zip TEXT,
    address_country TEXT,
    last_login_token TEXT,
    last_login_at TIMESTAMPTZ,
    role TEXT,
    skills TEXT[],
    status TEXT NOT NULL, -- ex.: 'active'/'inactive'
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, email)
);

CREATE INDEX idx_worker_status ON worker (tenant_id, status);

CREATE INDEX idx_worker_email ON worker (tenant_id, email);
-- Opcional: index GIN para array de skills
-- CREATE INDEX idx_worker_skills_gin ON worker USING GIN (skills);
CREATE TRIGGER trg_worker_updated_at
BEFORE UPDATE ON worker
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- SERVICE TYPE
CREATE TABLE service_type (
    id BIGINT PRIMARY KEY,
    tenant_id BIGINT NOT NULL REFERENCES tenant (id) ON DELETE CASCADE,
    code TEXT NOT NULL,
    name TEXT NOT NULL,
    description TEXT,
    duration_minutes INT,
    price NUMERIC(10, 2) NOT NULL DEFAULT 0,
    active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, code)
);

CREATE INDEX idx_service_type_code ON service_type (tenant_id, code);

CREATE INDEX idx_service_type_name ON service_type (tenant_id, name);

CREATE TRIGGER trg_service_type_updated_at
BEFORE UPDATE ON service_type
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- LANE (sub-filas por tenant)
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

-- PET
CREATE TABLE pet (
    id BIGINT PRIMARY KEY,
    tenant_id BIGINT NOT NULL REFERENCES tenant (id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    species TEXT NOT NULL, -- ex.: 'dog','cat'
    breed TEXT,
    sex TEXT,
    age INT,
    weight INT, -- defina unidade na aplicação (kg/g)
    microchip_id TEXT,
    notes TEXT,
    owner_id BIGINT NOT NULL,
    created_by BIGINT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, microchip_id),
    -- FK composta garantindo isolamento por tenant
    FOREIGN KEY (tenant_id, owner_id) REFERENCES owner (tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, created_by) REFERENCES worker (tenant_id, id) ON DELETE RESTRICT
);

CREATE INDEX idx_pet_tenant ON pet (tenant_id);

CREATE INDEX idx_pet_microchip_id ON pet (tenant_id, microchip_id);

CREATE INDEX idx_pet_owner_id ON pet (tenant_id, owner_id);

CREATE INDEX idx_pet_created_by ON pet (tenant_id, created_by);

CREATE TRIGGER trg_pet_updated_at
BEFORE UPDATE ON pet
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- TICKET (única definição, normalizada)
-- Nota: derivamos o owner pela FK via PET (não duplicamos owner_id no ticket)
CREATE TABLE ticket (
    tenant_id BIGINT NOT NULL REFERENCES tenant (id) ON DELETE CASCADE,
    id BIGINT NOT NULL,
    pet_id BIGINT NOT NULL,
    service_type_id BIGINT,
    lane_id BIGINT NOT NULL,
    status ticket_status NOT NULL,
    priority ticket_priority NOT NULL DEFAULT 'normal',
    position INT NOT NULL, -- posição na fila
    scheduled_at TIMESTAMPTZ,
    assigned_worker_id BIGINT,
    started_at TIMESTAMPTZ,
    finished_at TIMESTAMPTZ,
    created_by BIGINT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (tenant_id, id),
    -- FKs compostas
    FOREIGN KEY (tenant_id, pet_id) REFERENCES pet (tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, service_type_id) REFERENCES service_type (tenant_id, id) ON DELETE SET NULL,
    FOREIGN KEY (tenant_id, lane_id) REFERENCES lane (tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, assigned_worker_id) REFERENCES worker (tenant_id, id) ON DELETE SET NULL,
    FOREIGN KEY (tenant_id, created_by) REFERENCES worker (tenant_id, id) ON DELETE RESTRICT
);

CREATE INDEX idx_ticket_status ON ticket (tenant_id, status);

CREATE INDEX idx_ticket_priority ON ticket (tenant_id, priority);

CREATE INDEX idx_ticket_position ON ticket (tenant_id, position);

CREATE INDEX idx_ticket_pet_id ON ticket (tenant_id, pet_id);

CREATE INDEX idx_ticket_assigned_worker_id ON ticket (tenant_id, assigned_worker_id);

CREATE INDEX idx_ticket_service_type_id ON ticket (tenant_id, service_type_id);

CREATE TRIGGER trg_ticket_updated_at
BEFORE UPDATE ON ticket
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- =========================================================
-- TABELAS RELACIONADAS
-- =========================================================

-- TICKET SERVICE (um ticket pode ter 1..N serviços executados)
CREATE TABLE ticket_service (
    id BIGINT PRIMARY KEY,
    tenant_id BIGINT NOT NULL REFERENCES tenant (id) ON DELETE CASCADE,
    ticket_id BIGINT NOT NULL,
    service_type_id BIGINT NOT NULL,
    worker_id BIGINT NOT NULL,
    price NUMERIC(10, 2) NOT NULL CHECK (price >= 0),
    started_at TIMESTAMPTZ,
    finished_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    FOREIGN KEY (tenant_id, ticket_id) REFERENCES ticket (tenant_id, id) ON DELETE CASCADE,
    FOREIGN KEY (tenant_id, service_type_id) REFERENCES service_type (tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, worker_id) REFERENCES worker (tenant_id, id) ON DELETE RESTRICT
);

CREATE INDEX idx_ticket_service_ticket_id ON ticket_service (tenant_id, ticket_id);

CREATE INDEX idx_ticket_service_service_type_id ON ticket_service (tenant_id, service_type_id);

CREATE INDEX idx_ticket_service_worker_id ON ticket_service (tenant_id, worker_id);

-- TICKET EVENT (histórico/audit)
CREATE TABLE ticket_event (
    tenant_id BIGINT NOT NULL REFERENCES tenant (id) ON DELETE CASCADE,
    id BIGINT NOT NULL,
    ticket_id BIGINT NOT NULL,
    event_type ticket_event_type NOT NULL,
    event_data JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (tenant_id, id),
    FOREIGN KEY (tenant_id, ticket_id) REFERENCES ticket (tenant_id, id) ON DELETE CASCADE
);

CREATE INDEX idx_ticket_event_ticket_id ON ticket_event (tenant_id, ticket_id);

CREATE INDEX idx_ticket_event_type ON ticket_event (tenant_id, event_type);

-- ATTACHMENT (pode pertencer a um pet OU a um ticket)
CREATE TABLE attachment (
    id BIGINT PRIMARY KEY,
    tenant_id BIGINT NOT NULL REFERENCES tenant (id) ON DELETE CASCADE,
    pet_id BIGINT,
    ticket_id BIGINT,
    url TEXT NOT NULL,
    kind TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (
        pet_id IS NOT NULL
        OR ticket_id IS NOT NULL
    ),
    UNIQUE (tenant_id, id),
    -- Quando houver pet, garanta que é do mesmo tenant
    FOREIGN KEY (tenant_id, pet_id) REFERENCES pet (tenant_id, id) ON DELETE CASCADE,
    -- Quando houver ticket, garanta que é do mesmo tenant
    FOREIGN KEY (tenant_id, ticket_id) REFERENCES ticket (tenant_id, id) ON DELETE CASCADE
);

CREATE INDEX idx_attachment_pet_id ON attachment (tenant_id, pet_id);

CREATE INDEX idx_attachment_ticket_id ON attachment (tenant_id, ticket_id);

-- TICKET x WORKER (N:N, com papel e timestamp de entrada)
CREATE TABLE ticket_worker (
    tenant_id BIGINT NOT NULL REFERENCES tenant (id) ON DELETE CASCADE,
    ticket_id BIGINT NOT NULL,
    worker_id BIGINT NOT NULL,
    role TEXT,
    joined_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (
        tenant_id,
        ticket_id,
        worker_id
    ),
    FOREIGN KEY (tenant_id, ticket_id) REFERENCES ticket (tenant_id, id) ON DELETE CASCADE,
    FOREIGN KEY (tenant_id, worker_id) REFERENCES worker (tenant_id, id) ON DELETE RESTRICT
);

CREATE INDEX idx_ticket_worker_ticket_id ON ticket_worker (tenant_id, ticket_id);

CREATE INDEX idx_ticket_worker_worker_id ON ticket_worker (tenant_id, worker_id);

CREATE INDEX IF NOT EXISTS idx_pet_owner_created_at ON pet (
    tenant_id,
    owner_id,
    created_at DESC,
    id DESC
);

CREATE INDEX IF NOT EXISTS idx_pet_created_by_created_at ON pet (
    tenant_id,
    created_by,
    created_at DESC,
    id DESC
);
-- Busca por nome com ILIKE em escala:
CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE INDEX IF NOT EXISTS idx_pet_name_trgm ON pet USING GIN (name gin_trgm_ops);

CREATE INDEX IF NOT EXISTS idx_ticket_queue ON ticket (
    tenant_id,
    lane_id,
    status,
    position ASC,
    created_at ASC,
    id ASC
);

CREATE INDEX IF NOT EXISTS idx_ticket_lane ON ticket (tenant_id, lane_id);

CREATE INDEX IF NOT EXISTS idx_ticket_scheduled ON ticket (
    tenant_id,
    scheduled_at ASC,
    id ASC
);

CREATE INDEX IF NOT EXISTS idx_ticket_pet_created ON ticket (
    tenant_id,
    pet_id,
    created_at DESC,
    id DESC
);

CREATE INDEX IF NOT EXISTS idx_ticket_worker_created ON ticket (
    tenant_id,
    assigned_worker_id,
    created_at DESC,
    id DESC
);

CREATE INDEX IF NOT EXISTS idx_service_type_active_name ON service_type (
    tenant_id,
    active,
    name ASC,
    id ASC
);

CREATE INDEX IF NOT EXISTS idx_service_type_created_at ON service_type (
    tenant_id,
    created_at DESC,
    id DESC
);