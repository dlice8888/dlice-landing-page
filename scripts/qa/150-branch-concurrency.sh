#!/usr/bin/env bash
set -euo pipefail

: "${PGHOST:?PGHOST is required}"
: "${PGPORT:=5432}"
: "${PGUSER:=postgres}"
: "${PGPASSWORD:?PGPASSWORD is required}"

DB="dlice_150_branch_load"
TENANT_A="00000000-0000-4000-8000-000000000001"
TENANT_B="00000000-0000-4000-8000-000000000002"
LOG_DIR="$(mktemp -d /tmp/dlice-150-branch-XXXXXX)"
cleanup() {
  dropdb --if-exists "$DB" >/dev/null 2>&1 || true
  rm -rf "$LOG_DIR"
}
trap cleanup EXIT
export PGHOST PGPORT PGUSER PGPASSWORD

if ! command -v pgbench >/dev/null 2>&1; then
  apt-get update
  apt-get install -y --no-install-recommends postgresql-contrib-17
fi

psql -qv ON_ERROR_STOP=1 -d postgres <<'SQL'
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname='authenticated') THEN
    CREATE ROLE authenticated NOLOGIN;
  END IF;
END
$$;
SQL

dropdb --if-exists "$DB"
createdb "$DB"
psql -qv ON_ERROR_STOP=1 -d "$DB" <<SQL
CREATE TABLE public.tenants(id uuid PRIMARY KEY,tenant_code text NOT NULL UNIQUE);
CREATE TABLE public.branches(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.tenants(id),
  branch_code text NOT NULL,
  UNIQUE(tenant_id,id),
  UNIQUE(tenant_id,branch_code)
);
CREATE INDEX branches_tenant_branch_code_idx ON public.branches(tenant_id,branch_code);
ALTER TABLE public.branches ENABLE ROW LEVEL SECURITY;
CREATE POLICY branch_tenant_isolation ON public.branches
  FOR SELECT TO authenticated
  USING (tenant_id=nullif(current_setting('app.tenant_id',true),'')::uuid);
GRANT SELECT ON public.branches TO authenticated;
INSERT INTO public.tenants(id,tenant_code) VALUES
  ('$TENANT_A','TENANT-A'),('$TENANT_B','TENANT-B');
INSERT INTO public.branches(tenant_id,branch_code)
SELECT '$TENANT_A','A-'||lpad(n::text,3,'0') FROM generate_series(1,150) n;
INSERT INTO public.branches(tenant_id,branch_code) VALUES ('$TENANT_B','B-001');
SQL

BRANCHES="$(psql -qAt -d "$DB" -c 'SELECT count(*) FROM public.branches')"
A_BRANCHES="$(psql -qAt -d "$DB" -c "SELECT count(*) FROM public.branches WHERE tenant_id='$TENANT_A'")"
B_BRANCHES="$(psql -qAt -d "$DB" -c "SELECT count(*) FROM public.branches WHERE tenant_id='$TENANT_B'")"
[[ "$BRANCHES" == "151" && "$A_BRANCHES" == "150" && "$B_BRANCHES" == "1" ]]

cat > "$LOG_DIR/tenant-a.sql" <<SQL
SET LOCAL ROLE authenticated;
SET LOCAL app.tenant_id='$TENANT_A';
SELECT CASE WHEN count(*)=150 THEN 1 ELSE 1/0 END FROM public.branches;
SELECT CASE WHEN count(*)=0 THEN 1 ELSE 1/0 END FROM public.branches WHERE tenant_id='$TENANT_B';
SQL
cat > "$LOG_DIR/tenant-b.sql" <<SQL
SET LOCAL ROLE authenticated;
SET LOCAL app.tenant_id='$TENANT_B';
SELECT CASE WHEN count(*)=1 THEN 1 ELSE 1/0 END FROM public.branches;
SELECT CASE WHEN count(*)=0 THEN 1 ELSE 1/0 END FROM public.branches WHERE tenant_id='$TENANT_A';
SQL

run_probe() {
  local tenant="$1" file="$2"
  local output="$LOG_DIR/$tenant.out"
  (
    cd "$LOG_DIR"
    pgbench -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$DB" \
      -n -c 50 -j 4 -T 10 -r -l --log-prefix="$tenant" -f "$file"
  ) | tee "$output"
  local failed
  failed="$(awk -F: '/number of failed transactions/ {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2}' "$output" | awk '{print $1}')"
  if [[ -z "$failed" || "$failed" != "0" ]]; then
    printf 'LOAD_ASSERT_FAILED tenant=%s failed_transactions=%s\n' "$tenant" "${failed:-missing}" >&2
    return 1
  fi
  local p95 p99
  p95="$(awk '{print $5}' "$LOG_DIR/$tenant".* 2>/dev/null | sort -n | awk '{a[NR]=$1} END {if(NR) print a[int(NR*0.95+0.999)]}')"
  p99="$(awk '{print $5}' "$LOG_DIR/$tenant".* 2>/dev/null | sort -n | awk '{a[NR]=$1} END {if(NR) print a[int(NR*0.99+0.999)]}')"
  printf 'tenant=%s transactions_p95_us=%s transactions_p99_us=%s\n' "$tenant" "${p95:-unavailable}" "${p99:-unavailable}"
}

run_probe tenant-a "$LOG_DIR/tenant-a.sql"
run_probe tenant-b "$LOG_DIR/tenant-b.sql"

printf 'BRANCH_CONCURRENCY_DRILL=PASS\n'
printf 'postgres_version=%s\n' "$(psql -qAt -d "$DB" -c 'SHOW server_version')"
printf 'branch_rows=%s tenant_a_branches=%s tenant_b_branches=%s\n' "$BRANCHES" "$A_BRANCHES" "$B_BRANCHES"
printf 'concurrent_clients=50 threads=4 duration_per_tenant_seconds=10\n'
printf 'NOTE=This is a local database read/isolation load probe, not a full 150-branch application or API performance certification.\n'
