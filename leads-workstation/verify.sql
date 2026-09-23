\set ON_ERROR_STOP on
\connect leads_workstation
SELECT current_database() AS database_name;
SELECT nspname FROM pg_namespace
 WHERE nspname IN ('lead_import_raw','leads','lead_audit','lead_ops')
 ORDER BY nspname;
SELECT table_schema, table_name
 FROM information_schema.tables
 WHERE table_schema IN ('leads','lead_audit','lead_ops')
 ORDER BY table_schema, table_name;
SELECT rolname
 FROM pg_roles
 WHERE rolname IN ('leads_owner','leads_importer','leads_app','leads_readonly','n8n')
 ORDER BY rolname;
