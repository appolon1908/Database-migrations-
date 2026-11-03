# Leads Workstation database verification — 2026-09-23

Scope: local Ubuntu backup/recovery node only. No remote/staging/production database mutation is authorized or performed.

## Scheduled backup policy verification

- `bash -n`: PASS.
- `shellcheck`: PASS.
- `systemd-analyze verify` for the backup service/timer: PASS.
- Non-local host guard: PASS (`db.example.com` rejected with exit 64 before any connection attempt).
- Wrong database guard: PASS (`production` rejected with exit 64 before any connection attempt).
- Manual local dump: PASS.
  - `/home/codestra/Backups/Leads/leads_workstation_20260923T230530-0400.dump`
  - SHA-256 `65af34b67577612674be6ed7381d481e98a215f52c6a15ad09df02da41e2105c`
  - `pg_restore --list`: PASS.
- Disposable restore of that artifact: PASS.
  - required schemas: 4/4 (`lead_import_raw`, `leads`, `lead_audit`, `lead_ops`)
  - contract tables: 6
  - canonical lead count: 0
  - disposable verification database removed after test.
- Repo-backed systemd service execution: PASS.
  - service result: `success`
  - generated `/home/codestra/Backups/Leads/leads_workstation_20260923T230607-0400.dump`
  - SHA-256 `8c6b6f6e7bc92009996b84da923be1854698776dcd559a8e08a69475ee1536a2`
  - file + SHA + metadata permissions: `0600`, owner `codestra`.
  - SHA sidecar verification: PASS.
  - `pg_restore --list`: PASS.
- `codestra-leads-backup.timer`: enabled and active.
  - schedule: daily 02:15 local time, `Persistent=true`, randomized delay <= 10m.
  - first scheduled next execution observed for 2026-09-24 around 02:17 AST.

## Safety result

The backup policy is **Implemented and Verified locally**. It is not production authority, does not contact remote PostgreSQL endpoints, does not import lead data, and does not authorize N8N/provider effects. Hosted CI remains a separate release gate.


## 2026-09-24 governed promotion/provenance extension

- Added `lead_ops.import_row_manifest` and `lead_ops.promotion_candidates` to the local database contract.
- Provenance manifest is append-only for `leads_importer`: importer can `SELECT`/`INSERT` manifest rows but cannot insert promotion candidates or canonical leads.
- `leads_app` can read the manifest but cannot insert/update/delete it; promotion candidates must reference an exact `(import_batch_id, source_row, source_fingerprint)` manifest tuple.
- Frozen authority batch `35066e1b-bc98-46d2-8ece-368c386afd2d` manifest backfill: 104,677 rows / 104,677 distinct source rows / 104,677 distinct source fingerprints.
- Batch metadata records `provenance_manifest_verified=true`, `provenance_manifest_rows=104677`, while `promotion_authorized=false` and `rows_accepted=0` remain unchanged.
- Post-extension repo-backed backup service: PASS.
  - `/home/codestra/Backups/Leads/leads_workstation_20260924T020521-0400.dump`
  - SHA-256 `599d744eb48281a59f5449d0abda9c609f5a235b221d58c3cc3e94e4ef2a637d`
  - `pg_restore --list`: PASS.
- Disposable restore of that artifact: PASS.
  - required schemas: 4/4
  - contract tables: 8
  - provenance manifest rows: 104,677
  - governed raw authority rows: 104,677
  - canonical lead count: 0
  - restored batch gate: `promotion_authorized=false`, `provenance_manifest_verified=true`
  - disposable verification database removed after test.

This extension does not authorize canonical promotion. It strengthens the raw-to-candidate provenance boundary while preserving backup/local-only authority.
