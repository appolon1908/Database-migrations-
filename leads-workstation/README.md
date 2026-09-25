# Leads Workstation PostgreSQL contract

Branch: `mission/leads-workstation-integration-20260923`

This integration branch owns the database contract for the local Ubuntu Leads Workstation.

## Planned database

`leads_workstation`

## Planned schemas

- `lead_import_raw` — raw/provenance-preserving Meltano loads.
- `leads` — canonical lead records accessed through Leads-Workstation.
- `lead_audit` — change/audit evidence.
- `lead_ops` — import batches, duplicate-review queue, outbox and operational metadata.

## Least-privilege model

- Meltano importer: raw staging only.
- Leads API: canonical CRUD + required audit/outbox operations.
- N8N: no direct canonical writer role; use Leads API.
- Read-only reporting role: explicit views/select only.

No migration is applied until this contract is reviewed against the current Database-migrations repository conventions and the local PostgreSQL 18 instance.


## MCR-B projection schema

The additive `0002_mcr_projection_read_model.sql` migration defines tenant-bound lifecycle,
channel-health, suppression, exposure, and delivery projections consumed by Leads-Workstation.
Middleware MCR-C remains the decision/execution authority. `leads_app` and
`leads_readonly` receive SELECT-only access to these projection tables.
