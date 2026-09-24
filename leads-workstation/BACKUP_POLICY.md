# Local Leads PostgreSQL backup policy

Authority: backup/local recovery only. This policy must never target a remote, staging, or production PostgreSQL endpoint.

## Guardrails

- The script refuses any database host other than `127.0.0.1`, `localhost`, or `::1`.
- The script refuses any database name other than `leads_workstation`.
- Credentials are loaded from the local protected environment file and are never stored in this repository.
- Dumps use PostgreSQL custom format with owner/ACL replay disabled.
- Every dump must pass `pg_restore --list` before it is promoted from the temporary filename.
- A SHA-256 sidecar and metadata sidecar are emitted next to every successful dump.
- The metadata records canonical lead count at backup time; it contains no lead payload.
- Backup files are mode `0600`; the backup directory is mode `0700`.
- A non-blocking `flock` prevents overlapping scheduled runs.
- Default retention is 14 days. Retention removes only this policy's timestamped dump plus its matching sidecars.
- The systemd service denies non-loopback IP access and permits writes only under `/home/codestra/Backups/Leads`.

## Schedule

The repository timer runs daily at 02:15 local system time with up to 10 minutes of randomized delay and `Persistent=true` so a missed run is recovered after the workstation returns online.

## Validation

A release gate is green only when all of the following are proven on the backup workstation:

1. `systemd-analyze verify` accepts the service and timer.
2. The backup script completes against local PostgreSQL.
3. `pg_restore --list` succeeds for the produced artifact.
4. The sidecar SHA-256 matches the dump.
5. A disposable restore test succeeds before final certification.
6. No remote PostgreSQL endpoint is contacted.

This policy does not authorize real lead ingestion, production effects, or promotion of this backup node to source-of-truth.
- Backups authenticate with the least-privilege `leads_readonly` role; dynamic `lead_import_raw` tables grant read access through `leads_importer` default privileges so raw recovery data is included without granting raw access to `leads_app`.
