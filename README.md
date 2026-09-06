# Codestra Database Migrations

Canonical, review-gated database migration packages for Appolon-owned services. Production application remains separately authorized and fail-closed.

Certification verifies the imported source provenance, compiles every Python
migration, rejects missing or duplicate parents and cycles, and requires the
single expected Alembic head `0059_klyrow_usage_events`. Passing CI certifies a
source candidate only; it does not authorize applying migrations to production.
