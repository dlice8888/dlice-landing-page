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
create or replace function public.bi_publish_metric_snapshot(p_snapshot_id uuid,p_actor_user_id uuid)
returns jsonb language plpgsql security invoker set search_path=''
as $
declare v public.bi_metric_snapshots%rowtype; v_sla integer;
begin
 select * into v from public.bi_metric_snapshots where id=p_snapshot_id for update;
 if not found then raise exception using errcode='P0002',message='BI_SNAPSHOT_NOT_FOUND'; end if;
 if v.status not in ('draft','validated') then raise exception using errcode='23514',message='BI_SNAPSHOT_NOT_PUBLISHABLE'; end if;
 select freshness_sla_minutes into v_sla from public.bi_metric_definitions where id=v.metric_id and active=true and formula_version=v.formula_version;
 if not found then raise exception using errcode='23514',message='BI_METRIC_VERSION_INACTIVE'; end if;
 if cardinality(v.source_watermark_ids)=0 or cardinality(v.reconciliation_run_ids)=0 then raise exception using errcode='23514',message='BI_EVIDENCE_REQUIRED'; end if;
 if exists(select 1 from unnest(v.source_watermark_ids) x(id) left join public.bi_source_watermarks w on w.id=x.id and w.tenant_id=v.tenant_id where w.id is null or w.status<>'complete' or w.source_window_end<v.period_end or w.ingested_at<now()-make_interval(mins=>v_sla)) then
  raise exception using errcode='23514',message='BI_SOURCE_STALE_OR_INCOMPLETE';
 end if;
 if exists(select 1 from unnest(v.reconciliation_run_ids) x(id) left join public.bi_reconciliation_runs r on r.id=x.id and r.tenant_id=v.tenant_id where r.id is null or r.status<>'passed' or r.period_start>v.period_start::date or r.period_end<v.period_end::date) then
  raise exception using errcode='23514',message='BI_RECONCILIATION_NOT_PASSED';
 end if;
 update public.bi_metric_snapshots set status='published',published_at=now(),published_by=p_actor_user_id where id=p_snapshot_id;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'bi.metric_snapshot.published','bi_metric_snapshot',p_snapshot_id::text,jsonb_build_object('tenant_id',v.tenant_id,'metric_id',v.metric_id,'formula_version',v.formula_version));
 return jsonb_build_object('snapshot_id',p_snapshot_id,'status','published');
end $;
revoke all on function public.bi_publish_metric_snapshot(uuid,uuid) from public,anon,authenticated;
grant execute on function public.bi_publish_metric_snapshot(uuid,uuid) to service_role;

-- Snapshot publishing RPC must verify every referenced watermark is complete and fresh,
-- every reconciliation run passed, metric version matches, and caller has BI publish authority.


-- Versioned metric lineage: a metric cannot be published until every declared
-- source entity has an explicit field/key/aggregation mapping for that formula.
create table if not exists public.bi_metric_source_lineage (
 id uuid primary key default gen_random_uuid(),
 metric_id uuid not null references public.bi_metric_definitions(id) on delete restrict,
 formula_version integer not null check(formula_version>0),
 source_entity text not null,
 source_field text not null,
 source_key text not null,
 join_rule text not null,
 aggregation_rule text not null,
 transformation_reference text not null,
 approved_by uuid not null references auth.users(id) on delete restrict,
 approved_at timestamptz not null,
 created_at timestamptz not null default now(),
 unique(metric_id,formula_version,source_entity,source_field,source_key),
 check(length(btrim(source_entity)) between 2 and 100),
 check(length(btrim(source_field)) between 1 and 160),
 check(length(btrim(source_key)) between 1 and 160),
 check(length(btrim(join_rule)) between 3 and 500),
 check(length(btrim(aggregation_rule)) between 3 and 500),
 check(length(btrim(transformation_reference)) between 3 and 500)
);
alter table public.bi_metric_source_lineage enable row level security;
drop policy if exists service_role_only on public.bi_metric_source_lineage;
create policy service_role_only on public.bi_metric_source_lineage for all to service_role using(true) with check(true);
revoke all on public.bi_metric_source_lineage from anon,authenticated;
grant select,insert,update,delete on public.bi_metric_source_lineage to service_role;

create or replace function public.bi_enforce_snapshot_lineage()
returns trigger language plpgsql security invoker set search_path=''
as $$
declare
 v_sources text[];
 v_version integer;
 v_sla integer;
 v_missing text[];
 v_bad_watermarks integer;
 v_bad_reconciliations integer;
begin
 if new.status<>'published' then return new; end if;
 select source_entities,formula_version,freshness_sla_minutes
 into v_sources,v_version,v_sla
 from public.bi_metric_definitions where id=new.metric_id and active=true;
 if not found or v_version<>new.formula_version then
  raise exception using errcode='23514',message='BI_METRIC_FORMULA_VERSION_MISMATCH';
 end if;

 select array_agg(src) into v_missing from unnest(v_sources) src
 where not exists(select 1 from public.bi_metric_source_lineage l
  where l.metric_id=new.metric_id and l.formula_version=new.formula_version and l.source_entity=src);
 if coalesce(cardinality(v_missing),0)>0 then
  raise exception using errcode='23514',message='BI_METRIC_SOURCE_LINEAGE_INCOMPLETE';
 end if;

 if coalesce(cardinality(new.source_watermark_ids),0)=0
   or coalesce(cardinality(new.reconciliation_run_ids),0)=0 then
  raise exception using errcode='23514',message='BI_SNAPSHOT_EVIDENCE_REQUIRED';
 end if;

 select count(*) into v_bad_watermarks
 from unnest(new.source_watermark_ids) selected(id)
 left join public.bi_source_watermarks w
   on w.id=selected.id and w.tenant_id=new.tenant_id
 where w.id is null
    or w.status<>'complete'
    or w.source_window_start>new.period_start
    or w.source_window_end<new.period_end
    or w.created_at<now()-make_interval(mins=>v_sla)
    or w.expected_record_count is null
    or w.observed_record_count<>w.expected_record_count;
 if v_bad_watermarks>0 then
  raise exception using errcode='23514',message='BI_SOURCE_WATERMARK_INCOMPLETE_STALE_OR_OUT_OF_SCOPE';
 end if;

 select array_agg(src) into v_missing from unnest(v_sources) src
 where not exists(
  select 1 from unnest(new.source_watermark_ids) selected(id)
  join public.bi_source_watermarks w on w.id=selected.id
  where w.tenant_id=new.tenant_id and w.source_key=src
    and w.status='complete'
    and w.source_window_start<=new.period_start
    and w.source_window_end>=new.period_end
    and w.created_at>=now()-make_interval(mins=>v_sla)
    and w.expected_record_count is not null
    and w.observed_record_count=w.expected_record_count
 );
 if coalesce(cardinality(v_missing),0)>0 then
  raise exception using errcode='23514',message='BI_SOURCE_WATERMARK_MISSING_FOR_SOURCE';
 end if;

 select count(*) into v_bad_reconciliations
 from unnest(new.reconciliation_run_ids) selected(id)
 left join public.bi_reconciliation_runs r
   on r.id=selected.id and r.tenant_id=new.tenant_id
 where r.id is null or r.status<>'passed'
    or r.period_start>new.period_start::date
    or r.period_end<new.period_end::date
    or r.reviewed_by is null or r.reviewed_at is null;
 if v_bad_reconciliations>0 then
  raise exception using errcode='23514',message='BI_RECONCILIATION_NOT_PASSED_OR_OUT_OF_SCOPE';
 end if;
 return new;
end $$;
drop trigger if exists bi_snapshot_lineage_guard on public.bi_metric_snapshots;
create trigger bi_snapshot_lineage_guard before insert or update of status,metric_id,formula_version
 on public.bi_metric_snapshots for each row execute function public.bi_enforce_snapshot_lineage();
