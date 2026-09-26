#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SQL = ROOT / "leads-workstation/0002_mcr_projection_read_model.sql"

EXPECTED_TABLES = [
    "mcr_lead_projection",
    "mcr_channel_health_projection",
    "mcr_suppression_projection",
    "mcr_exposure_projection",
    "mcr_delivery_projection",
]

def main() -> int:
    text = SQL.read_text(encoding="utf-8")
    upper = text.upper()
    errors = []
    for table in EXPECTED_TABLES:
        if f"CREATE TABLE IF NOT EXISTS leads.{table}" not in text:
            errors.append(f"missing table {table}")
    for required in (
        "PRIMARY KEY (tenant_id, lead_id)",
        "GRANT USAGE ON SCHEMA leads TO leads_app",
        "GRANT USAGE ON SCHEMA leads TO leads_readonly",
        "GRANT SELECT",
        "source_sha text NOT NULL",
    ):
        if required not in text:
            errors.append(f"missing invariant {required}")
    for forbidden in ("DROP TABLE", "TRUNCATE ", "DELETE FROM", "INSERT INTO", "UPDATE LEADS."):
        if forbidden in upper:
            errors.append(f"forbidden destructive/effect statement {forbidden}")
    if errors:
        print("MCR_B_PROJECTION_SCHEMA=FAIL")
        for error in errors:
            print("ERROR=" + error)
        return 1
    print("MCR_B_PROJECTION_SCHEMA=PASS")
    print("TABLES=" + str(len(EXPECTED_TABLES)))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
