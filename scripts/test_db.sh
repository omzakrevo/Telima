#!/usr/bin/env bash
# Recrée une base locale, applique le stub Supabase + toutes les migrations, puis les tests.
set -e
P="psql -h ${PGHOST:-/tmp} -p ${PGPORT:-5433} -U postgres -v ON_ERROR_STOP=1 -q"
psql -h ${PGHOST:-/tmp} -p ${PGPORT:-5433} -U postgres -q -c "drop database if exists telima_test" -c "create database telima_test"
$P -d telima_test -f supabase/tests/00_supabase_stub.sql
for f in supabase/migrations/*.sql; do echo "→ $f"; $P -d telima_test -f "$f"; done
for f in supabase/tests/[1-9]*.sql; do [ -f "$f" ] && { echo "→ $f"; $P -d telima_test -f "$f"; }; done
echo "OK"
