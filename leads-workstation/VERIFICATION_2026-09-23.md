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
