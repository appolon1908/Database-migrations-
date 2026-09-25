-- MCR-B Leads lifecycle/journey projection read model.
-- Authority: Leads-Workstation read model. Decisioning remains Middleware MCR-C.
-- Additive only; no provider effects or campaign execution.

CREATE SCHEMA IF NOT EXISTS leads;

CREATE TABLE IF NOT EXISTS leads.mcr_lead_projection (
    tenant_id text NOT NULL,
    lead_id uuid NOT NULL,
    lifecycle_state text NOT NULL CHECK (lifecycle_state IN (
        'NEW','VALIDATED','ELIGIBLE','ACTIVE_CYCLE','ENGAGED',
        'COOLING','REACTIVATION','CONVERTED','SUPPRESSED'
    )),
    lifecycle_version bigint NOT NULL CHECK (lifecycle_version > 0),
    engagement_score double precision NULL,
    next_eligible_at timestamptz NULL,
    next_action_reason text NULL,
    middleware_decision_id text NULL,
    source_sha text NOT NULL,
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (tenant_id, lead_id)
);

CREATE INDEX IF NOT EXISTS ix_mcr_lead_projection_queue
    ON leads.mcr_lead_projection (tenant_id, lifecycle_state, next_eligible_at, updated_at DESC);

CREATE TABLE IF NOT EXISTS leads.mcr_channel_health_projection (
    tenant_id text NOT NULL,
    lead_id uuid NOT NULL,
    channel text NOT NULL CHECK (channel IN ('email','sms','whatsapp','voice')),
    address_ref text NOT NULL,
    state text NOT NULL CHECK (state IN (
        'unknown','valid','possible','soft_bounce','hard_bounce',
        'complained','unsubscribed','suppressed','invalid'
    )),
    occurred_at timestamptz NULL,
    source_sha text NOT NULL,
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (tenant_id, lead_id, channel, address_ref)
);

CREATE INDEX IF NOT EXISTS ix_mcr_channel_health_projection_lead
    ON leads.mcr_channel_health_projection (tenant_id, lead_id, channel);

CREATE TABLE IF NOT EXISTS leads.mcr_suppression_projection (
    tenant_id text NOT NULL,
    suppression_id text NOT NULL,
    lead_id uuid NOT NULL,
    scope text NOT NULL,
    channel text NULL,
    campaign_id text NULL,
    reason text NOT NULL,
    occurred_at timestamptz NULL,
    source_sha text NOT NULL,
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (tenant_id, suppression_id)
);

CREATE INDEX IF NOT EXISTS ix_mcr_suppression_projection_lead
    ON leads.mcr_suppression_projection (tenant_id, lead_id, occurred_at DESC);

CREATE TABLE IF NOT EXISTS leads.mcr_exposure_projection (
    tenant_id text NOT NULL,
    lead_id uuid NOT NULL,
    campaign_id text NOT NULL,
    campaign_version integer NOT NULL CHECK (campaign_version > 0),
    channel text NOT NULL CHECK (channel IN ('email','sms','whatsapp','voice')),
    touch_index integer NOT NULL CHECK (touch_index > 0),
    status text NOT NULL,
    reserved_at timestamptz NULL,
    engagement_outcome text NULL,
    negative_outcome text NULL,
    middleware_decision_id text NULL,
    source_sha text NOT NULL,
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (
        tenant_id, lead_id, campaign_id, campaign_version, channel, touch_index
    )
);

CREATE INDEX IF NOT EXISTS ix_mcr_exposure_projection_journey
    ON leads.mcr_exposure_projection (tenant_id, lead_id, reserved_at DESC);

CREATE TABLE IF NOT EXISTS leads.mcr_delivery_projection (
    tenant_id text NOT NULL,
    event_id text NOT NULL,
    lead_id uuid NOT NULL,
    event_type text NOT NULL,
    channel text NOT NULL CHECK (channel IN ('email','sms','whatsapp','voice')),
    campaign_id text NULL,
    occurred_at timestamptz NULL,
    projection_state text NULL,
    source_sha text NOT NULL,
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (tenant_id, event_id)
);

CREATE INDEX IF NOT EXISTS ix_mcr_delivery_projection_journey
    ON leads.mcr_delivery_projection (tenant_id, lead_id, occurred_at DESC);

COMMENT ON TABLE leads.mcr_lead_projection IS
    'Read-only Leads projection of Middleware MCR-C lifecycle/next-action state.';
COMMENT ON TABLE leads.mcr_exposure_projection IS
    'Read-only campaign exposure projection; not campaign execution authority.';
COMMENT ON TABLE leads.mcr_delivery_projection IS
    'Read-only normalized delivery/engagement projection; no provider write authority.';

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'leads_app') THEN
        GRANT USAGE ON SCHEMA leads TO leads_app;
        GRANT SELECT ON
            leads.mcr_lead_projection,
            leads.mcr_channel_health_projection,
            leads.mcr_suppression_projection,
            leads.mcr_exposure_projection,
            leads.mcr_delivery_projection
        TO leads_app;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'leads_readonly') THEN
        GRANT USAGE ON SCHEMA leads TO leads_readonly;
        GRANT SELECT ON
            leads.mcr_lead_projection,
            leads.mcr_channel_health_projection,
            leads.mcr_suppression_projection,
            leads.mcr_exposure_projection,
            leads.mcr_delivery_projection
        TO leads_readonly;
    END IF;
END $$;
