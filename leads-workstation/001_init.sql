\set ON_ERROR_STOP on

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='leads_owner') THEN
    CREATE ROLE leads_owner NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='leads_importer') THEN
    CREATE ROLE leads_importer LOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='leads_app') THEN
    CREATE ROLE leads_app LOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='leads_readonly') THEN
    CREATE ROLE leads_readonly LOGIN;
  END IF;
END
$$;

ALTER ROLE leads_importer PASSWORD :'IMPORTER_PASSWORD';
ALTER ROLE leads_app PASSWORD :'APP_PASSWORD';
ALTER ROLE leads_readonly PASSWORD :'READONLY_PASSWORD';

SELECT 'CREATE DATABASE leads_workstation OWNER leads_owner'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname='leads_workstation')
\gexec

REVOKE ALL ON DATABASE leads_workstation FROM PUBLIC;
GRANT CONNECT ON DATABASE leads_workstation TO leads_importer, leads_app, leads_readonly;
GRANT TEMPORARY ON DATABASE leads_workstation TO leads_importer;

\connect leads_workstation

CREATE SCHEMA IF NOT EXISTS lead_import_raw AUTHORIZATION leads_owner;
CREATE SCHEMA IF NOT EXISTS leads AUTHORIZATION leads_owner;
CREATE SCHEMA IF NOT EXISTS lead_audit AUTHORIZATION leads_owner;
CREATE SCHEMA IF NOT EXISTS lead_ops AUTHORIZATION leads_owner;

REVOKE ALL ON SCHEMA lead_import_raw, leads, lead_audit, lead_ops FROM PUBLIC;
GRANT USAGE, CREATE ON SCHEMA lead_import_raw TO leads_importer;
GRANT USAGE ON SCHEMA leads, lead_audit, lead_ops TO leads_app, leads_readonly;

SET ROLE leads_owner;

CREATE TABLE IF NOT EXISTS lead_ops.import_batches (
  import_batch_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  source_name text NOT NULL,
  source_type text NOT NULL,
  source_location text,
  status text NOT NULL DEFAULT 'created'
    CHECK (status IN ('created','previewed','running','completed','failed','cancelled')),
  rows_seen bigint NOT NULL DEFAULT 0,
  rows_accepted bigint NOT NULL DEFAULT 0,
  rows_duplicate bigint NOT NULL DEFAULT 0,
  rows_review bigint NOT NULL DEFAULT 0,
  rows_rejected bigint NOT NULL DEFAULT 0,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  started_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS leads.leads (
  lead_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  business_name text NOT NULL CHECK (btrim(business_name) <> ''),
  contact_name text,
  country text NOT NULL CHECK (btrim(country) <> ''),
  state_province text,
  city text,
  business_category text NOT NULL CHECK (btrim(business_category) <> ''),
  campaign_source text,
  email text,
  phone text,
  website text,
  status text NOT NULL DEFAULT 'new'
    CHECK (status IN ('new','qualified','contacted','follow_up','converted','not_interested','invalid','archived')),
  owner_name text,
  priority text CHECK (priority IS NULL OR priority IN ('low','medium','high','urgent')),
  last_contact_at timestamptz,
  next_action text,
  notes text,
  source_file text,
  import_batch_id uuid REFERENCES lead_ops.import_batches(import_batch_id) ON DELETE SET NULL,
  duplicate_fingerprint text,
  version integer NOT NULL DEFAULT 1 CHECK (version > 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT country_business_are_distinct_fields CHECK (country IS DISTINCT FROM business_category)
);

CREATE INDEX IF NOT EXISTS idx_leads_country ON leads.leads(country);
CREATE INDEX IF NOT EXISTS idx_leads_business_category ON leads.leads(business_category);
CREATE INDEX IF NOT EXISTS idx_leads_status ON leads.leads(status);
CREATE INDEX IF NOT EXISTS idx_leads_owner ON leads.leads(owner_name);
CREATE INDEX IF NOT EXISTS idx_leads_duplicate_fingerprint ON leads.leads(duplicate_fingerprint);

CREATE TABLE IF NOT EXISTS leads.lead_activity (
  activity_id bigserial PRIMARY KEY,
  lead_id uuid NOT NULL REFERENCES leads.leads(lead_id) ON DELETE CASCADE,
  activity_type text NOT NULL,
  body text,
  actor text NOT NULL DEFAULT 'system',
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS lead_audit.lead_changes (
  audit_id bigserial PRIMARY KEY,
  lead_id uuid,
  action text NOT NULL,
  old_data jsonb,
  new_data jsonb,
  actor text NOT NULL,
  occurred_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS lead_ops.duplicate_review (
  review_id bigserial PRIMARY KEY,
  import_batch_id uuid REFERENCES lead_ops.import_batches(import_batch_id) ON DELETE CASCADE,
  source_row bigint,
  fingerprint text NOT NULL,
  candidate_lead_id uuid REFERENCES leads.leads(lead_id) ON DELETE SET NULL,
  match_score numeric(5,4),
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','accepted','rejected','merged')),
  raw_payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  resolved_at timestamptz
);

CREATE TABLE IF NOT EXISTS lead_ops.outbox (
  event_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_type text NOT NULL,
  aggregate_id uuid,
  payload jsonb NOT NULL,
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','delivered','failed','dead_letter')),
  attempts integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  delivered_at timestamptz
);

CREATE OR REPLACE FUNCTION leads.set_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  NEW.version = OLD.version + 1;
  RETURN NEW;
END
$$;

DROP TRIGGER IF EXISTS trg_leads_updated_at ON leads.leads;
CREATE TRIGGER trg_leads_updated_at
BEFORE UPDATE ON leads.leads
FOR EACH ROW EXECUTE FUNCTION leads.set_updated_at();

RESET ROLE;

GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA leads TO leads_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA leads TO leads_app;
GRANT SELECT, INSERT ON ALL TABLES IN SCHEMA lead_audit TO leads_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA lead_audit TO leads_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA lead_ops TO leads_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA lead_ops TO leads_app;

GRANT SELECT ON ALL TABLES IN SCHEMA leads, lead_audit, lead_ops TO leads_readonly;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA leads, lead_audit, lead_ops TO leads_readonly;

ALTER DEFAULT PRIVILEGES FOR ROLE leads_owner IN SCHEMA leads
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO leads_app;
ALTER DEFAULT PRIVILEGES FOR ROLE leads_owner IN SCHEMA leads
  GRANT USAGE, SELECT ON SEQUENCES TO leads_app;
ALTER DEFAULT PRIVILEGES FOR ROLE leads_owner IN SCHEMA lead_audit
  GRANT SELECT, INSERT ON TABLES TO leads_app;
ALTER DEFAULT PRIVILEGES FOR ROLE leads_owner IN SCHEMA lead_ops
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO leads_app;

-- No role/grant is created for N8N by design.
