# Leads Workstation PostgreSQL contract

Branch: `mission/leads-workstation-integration-20260923`

This integration branch owns the database contract for the local Ubuntu Leads Workstation.

## Planned database

`leads_workstation`

## Planned schemas

- `lead_import_raw` — raw/provenance-preserving Meltano loads.
- `leads` — canonical lead records accessed through Leads-Workstation.
- `lead_audit` — change/audit evidence.
- `lead_ops` — import batches, immutable row-provenance manifest, governed promotion-candidate queue, duplicate-review queue, outbox and operational metadata.

## Least-privilege model

- Meltano importer: raw staging plus append-only row-provenance manifest; no promotion decisions or canonical writes.
- Leads API: canonical CRUD + governed promotion-candidate review/promotion + required audit/outbox operations.
- N8N: no direct canonical writer role; use Leads API.
- Read-only reporting role: explicit views/select only.

No migration is applied until this contract is reviewed against the current Database-migrations repository conventions and the local PostgreSQL 18 instance.

## MCR-B projection schema

The additive `0002_mcr_projection_read_model.sql` migration defines tenant-bound lifecycle,
channel-health, suppression, exposure, and delivery projections consumed by Leads-Workstation.
Middleware MCR-C remains the decision/execution authority. `leads_app` and
`leads_readonly` receive SELECT-only access to these projection tables.

## Governed local backup policy

Scheduled backup artifacts are owned by this database contract. See `BACKUP_POLICY.md`, `backup-local.sh`, the repo-backed systemd units under `systemd/`, and `VERIFICATION_2026-09-23.md` for current local evidence. The policy is loopback-only, validates each dump with `pg_restore --list`, writes SHA-256 evidence, and does not authorize remote database access or real-data promotion.

## Promotion boundary

`lead_import_raw` remains importer-owned staging. The Leads API does **not** receive direct raw-schema privileges. Each staged row is first registered in `lead_ops.import_row_manifest` using only batch ID, source row and source fingerprint. Promotion candidates must reference that exact manifest tuple, are reviewed/approved explicitly, and may only become canonical rows through the Leads API. Promotion additionally requires verified provenance metadata plus the import batch metadata gate `promotion_authorized=true`; a frozen/raw-staged batch with that flag false cannot be promoted.
