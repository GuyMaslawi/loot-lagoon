#!/usr/bin/env bash
# Run supabase/migrations/*.sql against a throwaway local Postgres.
#
# Catches what reading cannot: a typo in a column name, a function that
# references a table it cannot see, a policy on a table that does not exist yet,
# a plpgsql body that does not compile. The alternative is finding out by
# pasting into the SQL Editor of the live project, where half the migration has
# already applied by the time the error appears.
#
# The stubs below stand in for the parts Supabase provides -- auth.users,
# auth.identities, auth.uid(), the roles, and pgcrypto in the `extensions`
# schema. They are deliberately minimal: enough for the migrations to compile
# and run, not an imitation of GoTrue.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PG="${PG_BIN:-/opt/homebrew/opt/postgresql@17/bin}"
[ -x "$PG/initdb" ] || { echo "no postgres at $PG (set PG_BIN)" >&2; exit 1; }

WORK="$(mktemp -d)"
cleanup() { "$PG/pg_ctl" -D "$WORK/data" -s -m immediate stop >/dev/null 2>&1 || true; rm -rf "$WORK"; }
trap cleanup EXIT

echo "==> initdb"
"$PG/initdb" -D "$WORK/data" -U postgres --auth=trust >/dev/null
echo "==> start"
"$PG/pg_ctl" -D "$WORK/data" -o "-k $WORK -c listen_addresses=''" -l "$WORK/log" -w start >/dev/null
export PGHOST="$WORK" PGUSER=postgres PGDATABASE=postgres
PSQL=("$PG/psql" -v ON_ERROR_STOP=1 -q --no-psqlrc)

echo "==> supabase stubs"
"${PSQL[@]}" >/dev/null <<'STUB'
create role anon           nologin;
create role authenticated  nologin;
create role service_role   nologin;

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

create schema if not exists auth;
create table auth.users (
    id    uuid primary key default gen_random_uuid(),
    email text
);
create table auth.identities (
    id       uuid primary key default gen_random_uuid(),
    user_id  uuid not null references auth.users (id) on delete cascade,
    provider text not null
);

-- GoTrue sets request.jwt.claims per request; the migrations only ever read
-- the subject out of it.
create or replace function auth.uid() returns uuid
language sql stable as $$
    select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;
STUB

fails=0
for f in "$ROOT"/supabase/migrations/*.sql; do
	printf '==> %s ... ' "$(basename "$f")"
	if out=$("${PSQL[@]}" -f "$f" 2>&1); then
		echo "ok"
	else
		echo "FAILED"
		echo "$out" | sed 's/^/      /'
		fails=$((fails + 1))
	fi
done

if [ "$fails" -eq 0 ]; then
	echo "==> re-running every migration, to prove they are idempotent"
	for f in "$ROOT"/supabase/migrations/*.sql; do
		printf '==> %s (again) ... ' "$(basename "$f")"
		if out=$("${PSQL[@]}" -f "$f" 2>&1); then
			echo "ok"
		else
			echo "FAILED ON RE-RUN"
			echo "$out" | sed 's/^/      /'
			fails=$((fails + 1))
		fi
	done
fi

if [ "$fails" -eq 0 ] && [ -f "$ROOT/tools/test_migrations.sql" ]; then
	echo "==> functional tests"
	# Raw. The assertions report through RAISE NOTICE, and when one fails the
	# exception text is the only thing that says which rule broke -- filtering
	# this output once cost an entire debugging round.
	if ! "${PSQL[@]}" -f "$ROOT/tools/test_migrations.sql" 2>&1; then
		fails=$((fails + 1))
	fi
fi

echo
[ "$fails" -eq 0 ] && echo "ALL MIGRATIONS OK" || echo "$fails MIGRATION(S) FAILED"
exit "$fails"
