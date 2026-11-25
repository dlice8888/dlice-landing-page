-- DESIGN DRAFT ONLY — NOT A MIGRATION.
-- KPI snapshots are tenant-scoped and publishable only after source freshness,
-- completeness and reconciliation are recorded. Never aggregate across tenants by default.
create table if not exists public.bi_metric_definitions (
 id uuid primary key default gen_random_uuid(),
 metric_key text not null unique,
 display_name text not null,
 description text not null,
 unit text not null check(unit in ('idr','count','percent','duration_seconds','ratio')),
 aggregation text not null check(aggregation in ('sum','count','average','ratio','distinct_count')),
 numerator_definition text null,
 denominator_definition text null,
 source_entities text[] not null,
 formula_version integer not null check(formula_version>0),
 owner_domain text not null,
 freshness_sla_minutes integer not null check(freshness_sla_minutes>0),
 active boolean not null default true,
 created_by uuid not null references auth.users(id) on delete restrict,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create table if not exists public.bi_source_watermarks (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete restrict,
 source_key text not null,
 source_window_start timestamptz not null,
 source_window_end timestamptz not null,
 max_source_updated_at timestamptz not null,
 expected_record_count bigint null check(expected_record_count is null or expected_record_count>=0),
 observed_record_count bigint not null check(observed_record_count>=0),
 completeness_ratio numeric(8,6) generated always as
  (case when expected_record_count is null or expected_record_count=0 then null else observed_record_count::numeric/expected_record_count end) stored,
 ingestion_run_id text not null,
 status text not null check(status in ('complete','partial','failed')),
 created_at timestamptz not null default now(),
 unique(tenant_id,source_key,source_window_start,source_window_end,ingestion_run_id),
 check(source_window_end>source_window_start),
 check(expected_record_count is null or observed_record_count<=expected_record_count)
);
create index if not exists bi_source_watermark_latest_idx on public.bi_source_watermarks(tenant_id,source_key,source_window_end desc);
create table if not exists public.bi_reconciliation_runs (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete restrict,
 period_start date not null,
 period_end date not null,
 source_domain text not null,
 source_reference text not null,
 expected_total numeric(20,4) not null,
 observed_total numeric(20,4) not null,
 variance numeric(20,4) generated always as (observed_total-expected_total) stored,
 tolerance numeric(20,4) not null default 0 check(tolerance>=0),
 status text not null check(status in ('pending','passed','failed','waived')),
 reviewed_by uuid null references auth.users(id) on delete restrict,
 reviewed_at timestamptz null,
 waiver_reason text null,
 created_at timestamptz not null default now(),
 check(period_end>=period_start),
 check(status<>'passed' or abs(observed_total-expected_total)<=tolerance),
 check(status<>'waived' or length(btrim(coalesce(waiver_reason,'')))>=10)
);
create table if not exists public.bi_metric_snapshots (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete restrict,
 metric_id uuid not null references public.bi_metric_definitions(id) on delete restrict,
 period_start timestamptz not null,
 period_end timestamptz not null,
 dimension_key text not null default 'all',
 dimension_value text not null default 'all',
 metric_value numeric(24,6) not null,
 source_watermark_ids uuid[] not null,
 reconciliation_run_ids uuid[] not null,
 formula_version integer not null,
 status text not null default 'draft' check(status in ('draft','validated','published','stale','rejected')),
 calculated_at timestamptz not null default now(),
 published_at timestamptz null,
 published_by uuid null references auth.users(id) on delete restrict,
 idempotency_key text not null,
 unique(tenant_id,id),
 unique(tenant_id,metric_id,period_start,period_end,dimension_key,dimension_value,formula_version),
 unique(tenant_id,idempotency_key),
 check(period_end>period_start),
 check(length(btrim(idempotency_key)) between 8 and 120),
 check(status<>'published' or (published_at is not null and published_by is not null and cardinality(source_watermark_ids)>0 and cardinality(reconciliation_run_ids)>0))
);
create index if not exists bi_snapshot_lookup_idx on public.bi_metric_snapshots(tenant_id,metric_id,period_end desc,status);
do $$
declare t text;
begin foreach t in array array['bi_metric_definitions','bi_source_watermarks','bi_reconciliation_runs','bi_metric_snapshots'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('drop policy if exists service_role_only on public.%I',t);
 execute format('create policy service_role_only on public.%I for all to service_role using(true) with check(true)',t);
 execute format('revoke all on public.%I from anon,authenticated',t);
 execute format('grant select,insert,update,delete on public.%I to service_role',t);
end loop; end $$;
-- Snapshot publishing RPC must verify every referenced watermark is complete and fresh,
-- every reconciliation run passed, metric version matches, and caller has BI publish authority.
