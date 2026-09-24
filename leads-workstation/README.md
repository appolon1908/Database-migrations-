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

## Governed local backup policy

Scheduled backup artifacts are owned by this database contract. See `BACKUP_POLICY.md`, `backup-local.sh`, the repo-backed systemd units under `systemd/`, and `VERIFICATION_2026-09-23.md` for current local evidence. The policy is loopback-only, validates each dump with `pg_restore --list`, writes SHA-256 evidence, and does not authorize remote database access or real-data promotion.
