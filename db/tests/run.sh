#!/usr/bin/env bash
# Builds a throwaway database, loads the schema and seed, and runs the tests.
# Needs a reachable Postgres 15+ and psql. Uses the usual PG* environment variables
# (PGHOST, PGPORT, PGUSER). Usage: PGHOST=localhost PGUSER=postgres db/tests/run.sh
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
DB="${TEST_DB:-journal_test}"
P="psql -v ON_ERROR_STOP=1 -q"

$P -d postgres -c "drop database if exists $DB" -c "create database $DB" 2>&1 | grep -v NOTICE || true
$P -d "$DB" -f "$here/00_supabase_stubs.sql"
$P -d "$DB" -f "$here/../schema.sql"
$P -d "$DB" -f "$here/../seed.sql"
$P -d "$DB" \
  -c "grant select, insert, update, delete on all tables in schema public to authenticated" \
  -c "grant select, insert, update, delete on storage.objects to authenticated" \
  -c "grant execute on all functions in schema public to authenticated"
$P -d "$DB" -f "$here/10_rls_and_scan_flow.sql" 2>&1 | grep -E 'NOTICE|ERROR|CONTEXT' | sed 's/^psql:[^ ]* //'
echo "All tests passed (any ERROR line above means a failure)."
