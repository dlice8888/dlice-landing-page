#!/usr/bin/env bash
set -euo pipefail

: "${PGHOST:?PGHOST is required}"
: "${PGPORT:=5432}"
: "${PGUSER:=postgres}"
: "${PGPASSWORD:?PGPASSWORD is required}"

SOURCE_DB="dlice_restore_source"
TARGET_DB="dlice_restore_target"
TENANT_A="00000000-0000-4000-8000-000000000001"
TENANT_B="00000000-0000-4000-8000-000000000002"
BACKUP_FILE="$(mktemp /tmp/dlice-restore-XXXXXX.dump)"
START_MS="$(date +%s%3N)"
cleanup() {
  dropdb --if-exists "$TARGET_DB" >/dev/null 2>&1 || true
  dropdb --if-exists "$SOURCE_DB" >/dev/null 2>&1 || true
  rm -f "$BACKUP_FILE"
}
trap cleanup EXIT

export PGHOST PGPORT PGUSER PGPASSWORD
psql -v ON_ERROR_STOP=1 -d postgres <<'SQL'
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname='authenticated') THEN
    CREATE ROLE authenticated NOLOGIN;
  END IF;
END
$$;
SQL

dropdb --if-exists "$TARGET_DB"
dropdb --if-exists "$SOURCE_DB"
createdb "$SOURCE_DB"

psql -v ON_ERROR_STOP=1 -d "$SOURCE_DB" <<SQL
CREATE TABLE public.tenants (
  id uuid PRIMARY KEY,
  tenant_code text NOT NULL UNIQUE
);
CREATE TABLE public.branches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.tenants(id),
  branch_code text NOT NULL,
  UNIQUE (tenant_id,id),
  UNIQUE (tenant_id,branch_code)
);
CREATE TABLE public.operational_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.tenants(id),
  branch_id uuid NOT NULL,
  idempotency_key text NOT NULL,
  amount_minor bigint NOT NULL CHECK (amount_minor>=0),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id,idempotency_key),
  FOREIGN KEY (tenant_id,branch_id) REFERENCES public.branches(tenant_id,id)
);
CREATE INDEX operational_events_tenant_branch_created_idx
  ON public.operational_events(tenant_id,branch_id,created_at);
ALTER TABLE public.branches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.operational_events ENABLE ROW LEVEL SECURITY;
CREATE POLICY branch_tenant_isolation ON public.branches
  FOR SELECT TO authenticated
  USING (tenant_id = nullif(current_setting('app.tenant_id',true),'')::uuid);
CREATE POLICY event_tenant_isolation ON public.operational_events
  FOR SELECT TO authenticated
  USING (tenant_id = nullif(current_setting('app.tenant_id',true),'')::uuid);
GRANT SELECT ON public.branches,public.operational_events TO authenticated;

INSERT INTO public.tenants(id,tenant_code) VALUES
  ('$TENANT_A','TENANT-A'),
  ('$TENANT_B','TENANT-B');

INSERT INTO public.branches(tenant_id,branch_code)
SELECT '$TENANT_A', 'A-'||lpad(n::text,3,'0')
FROM generate_series(1,150) n;
INSERT INTO public.branches(tenant_id,branch_code)
VALUES ('$TENANT_B','B-001');

INSERT INTO public.operational_events(tenant_id,branch_id,idempotency_key,amount_minor)
SELECT b.tenant_id,b.id,'snapshot-'||b.branch_code,10000
FROM public.branches b;
SQL

EXPECTED_BRANCHES="$(psql -v ON_ERROR_STOP=1 -At -d "$SOURCE_DB" -c 'SELECT count(*) FROM public.branches')"
EXPECTED_EVENTS="$(psql -v ON_ERROR_STOP=1 -At -d "$SOURCE_DB" -c 'SELECT count(*) FROM public.operational_events')"
EXPECTED_CHECKSUM="$(psql -v ON_ERROR_STOP=1 -At -d "$SOURCE_DB" -c "SELECT md5(string_agg(tenant_id::text||':'||branch_id::text||':'||idempotency_key||':'||amount_minor::text,E'\\n' ORDER BY tenant_id,branch_id,idempotency_key)) FROM public.operational_events")"

# The snapshot includes every committed row before this point.
pg_dump --format=custom --no-owner --file="$BACKUP_FILE" "$SOURCE_DB"
BACKUP_BYTES="$(wc -c < "$BACKUP_FILE" | tr -d ' ')"

# One committed row after the snapshot is intentionally not expected in restore.
psql -v ON_ERROR_STOP=1 -d "$SOURCE_DB" <<'SQL'
INSERT INTO public.operational_events(tenant_id,branch_id,idempotency_key,amount_minor)
SELECT b.tenant_id,b.id,'post-snapshot-intentional',999
FROM public.branches b
WHERE b.branch_code='A-001';
SQL

RESTORE_START_MS="$(date +%s%3N)"
createdb "$TARGET_DB"
pg_restore --exit-on-error --no-owner --dbname="$TARGET_DB" "$BACKUP_FILE"

RESTORED_BRANCHES="$(psql -v ON_ERROR_STOP=1 -At -d "$TARGET_DB" -c 'SELECT count(*) FROM public.branches')"
RESTORED_EVENTS="$(psql -v ON_ERROR_STOP=1 -At -d "$TARGET_DB" -c 'SELECT count(*) FROM public.operational_events')"
RESTORED_CHECKSUM="$(psql -v ON_ERROR_STOP=1 -At -d "$TARGET_DB" -c "SELECT md5(string_agg(tenant_id::text||':'||branch_id::text||':'||idempotency_key||':'||amount_minor::text,E'\\n' ORDER BY tenant_id,branch_id,idempotency_key)) FROM public.operational_events")"
RLS_TABLES="$(psql -v ON_ERROR_STOP=1 -At -d "$TARGET_DB" -c "SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relname IN ('branches','operational_events') AND c.relrowsecurity")"
A_BRANCHES="$(psql -v ON_ERROR_STOP=1 -At -d "$TARGET_DB" -c "BEGIN; SET ROLE authenticated; SET app.tenant_id='$TENANT_A'; SELECT count(*) FROM public.branches; COMMIT" | tail -n 1)"
A_EVENTS="$(psql -v ON_ERROR_STOP=1 -At -d "$TARGET_DB" -c "BEGIN; SET ROLE authenticated; SET app.tenant_id='$TENANT_A'; SELECT count(*) FROM public.operational_events; COMMIT" | tail -n 1)"
B_BRANCHES="$(psql -v ON_ERROR_STOP=1 -At -d "$TARGET_DB" -c "BEGIN; SET ROLE authenticated; SET app.tenant_id='$TENANT_B'; SELECT count(*) FROM public.branches; COMMIT" | tail -n 1)"
B_EVENTS="$(psql -v ON_ERROR_STOP=1 -At -d "$TARGET_DB" -c "BEGIN; SET ROLE authenticated; SET app.tenant_id='$TENANT_B'; SELECT count(*) FROM public.operational_events; COMMIT" | tail -n 1)"
CROSS_TENANT="$(psql -v ON_ERROR_STOP=1 -At -d "$TARGET_DB" -c "BEGIN; SET ROLE authenticated; SET app.tenant_id='$TENANT_A'; SELECT count(*) FROM public.operational_events WHERE tenant_id='$TENANT_B'; COMMIT" | tail -n 1)"
SOURCE_AFTER="$(psql -v ON_ERROR_STOP=1 -At -d "$SOURCE_DB" -c 'SELECT count(*) FROM public.operational_events')"
END_MS="$(date +%s%3N)"
RTO_MS="$((END_MS-RESTORE_START_MS))"
POST_SNAPSHOT_ROWS="$((SOURCE_AFTER-RESTORED_EVENTS))"
PRE_SNAPSHOT_LOST="$((EXPECTED_EVENTS-RESTORED_EVENTS))"

[[ "$RESTORED_BRANCHES" == "$EXPECTED_BRANCHES" ]]
[[ "$RESTORED_EVENTS" == "$EXPECTED_EVENTS" ]]
[[ "$RESTORED_CHECKSUM" == "$EXPECTED_CHECKSUM" ]]
[[ "$RLS_TABLES" == "2" ]]
[[ "$A_BRANCHES" == "150" && "$A_EVENTS" == "150" ]]
[[ "$B_BRANCHES" == "1" && "$B_EVENTS" == "1" ]]
[[ "$CROSS_TENANT" == "0" ]]
[[ "$PRE_SNAPSHOT_LOST" == "0" ]]
[[ "$POST_SNAPSHOT_ROWS" == "1" ]]

printf 'BACKUP_RESTORE_DRILL=PASS\n'
printf 'postgres_version=%s\n' "$(psql -At -d "$TARGET_DB" -c 'SHOW server_version')"
printf 'backup_bytes=%s\n' "$BACKUP_BYTES"
printf 'restored_branches=%s\n' "$RESTORED_BRANCHES"
printf 'restored_events=%s\n' "$RESTORED_EVENTS"
printf 'pre_snapshot_committed_rows_lost=%s\n' "$PRE_SNAPSHOT_LOST"
printf 'post_snapshot_intentional_rows_not_restored=%s\n' "$POST_SNAPSHOT_ROWS"
printf 'tenant_a_visible_branches=%s\n' "$A_BRANCHES"
printf 'tenant_b_visible_branches=%s\n' "$B_BRANCHES"
printf 'cross_tenant_event_rows_visible=%s\n' "$CROSS_TENANT"
printf 'restored_rls_tables=%s\n' "$RLS_TABLES"
printf 'restore_drill_rto_ms=%s\n' "$RTO_MS"
printf 'NOTE=This is a disposable local PostgreSQL rehearsal, not a Supabase managed-backup RPO/RTO certification.\n'
