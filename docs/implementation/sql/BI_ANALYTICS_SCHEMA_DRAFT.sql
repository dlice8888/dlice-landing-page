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
as $$
declare v public.bi_metric_snapshots%rowtype; v_sla integer;
begin
 select * into v from public.bi_metric_snapshots where id=p_snapshot_id for update;
 if not found then raise exception using errcode='P0002',message='BI_SNAPSHOT_NOT_FOUND'; end if;
 if v.status not in ('draft','validated') then raise exception using errcode='23514',message='BI_SNAPSHOT_NOT_PUBLISHABLE'; end if;
 if v.created_by is null or v.created_by=p_actor_user_id then raise exception using errcode='42501',message='INDEPENDENT_BI_SNAPSHOT_PUBLISHER_REQUIRED'; end if;
 select freshness_sla_minutes into v_sla from public.bi_metric_definitions where id=v.metric_id and active=true and formula_version=v.formula_version;
 if not found then raise exception using errcode='23514',message='BI_METRIC_VERSION_INACTIVE'; end if;
 if cardinality(v.source_watermark_ids)=0 or cardinality(v.reconciliation_run_ids)=0 then raise exception using errcode='23514',message='BI_EVIDENCE_REQUIRED'; end if;
 if exists(select 1 from unnest(v.source_watermark_ids) x(id) left join public.bi_source_watermarks w on w.id=x.id and w.tenant_id=v.tenant_id where w.id is null or w.status<>'complete' or w.source_window_end<v.period_end or w.max_source_updated_at<now()-make_interval(mins=>v_sla)) then
  raise exception using errcode='23514',message='BI_SOURCE_STALE_OR_INCOMPLETE';
 end if;
 if exists(select 1 from unnest(v.reconciliation_run_ids) x(id) left join public.bi_reconciliation_runs r on r.id=x.id and r.tenant_id=v.tenant_id where r.id is null or r.status<>'passed' or r.period_start>v.period_start::date or r.period_end<v.period_end::date) then
  raise exception using errcode='23514',message='BI_RECONCILIATION_NOT_PASSED';
 end if;
 update public.bi_metric_snapshots set status='published',published_at=now(),published_by=p_actor_user_id where id=p_snapshot_id;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'bi.metric_snapshot.published','bi_metric_snapshot',p_snapshot_id::text,jsonb_build_object('tenant_id',v.tenant_id,'metric_id',v.metric_id,'formula_version',v.formula_version));
 return jsonb_build_object('snapshot_id',p_snapshot_id,'status','published');
end $$;
revoke all on function public.bi_publish_metric_snapshot(uuid,uuid) from public,anon,authenticated;
grant execute on function public.bi_publish_metric_snapshot(uuid,uuid) to service_role;


-- Evidence ingestion/reconciliation RPCs. Workers create evidence; a different
-- reviewer must approve reconciliation before snapshots can be published.
alter table public.bi_reconciliation_runs
 add column if not exists created_by uuid null references auth.users(id) on delete restrict,
 add column if not exists idempotency_key text null;
create unique index if not exists bi_reconciliation_idempotency_uq
 on public.bi_reconciliation_runs(tenant_id,idempotency_key) where idempotency_key is not null;
alter table public.bi_metric_snapshots
 add column if not exists created_by uuid null references auth.users(id) on delete restrict;

create or replace function public.bi_record_source_watermark(
 p_tenant_id uuid,p_source_key text,p_window_start timestamptz,p_window_end timestamptz,
 p_max_source_updated_at timestamptz,p_expected_count bigint,p_observed_count bigint,
 p_ingestion_run_id text,p_actor_user_id uuid
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v public.bi_source_watermarks%rowtype; v_status text;
begin
 if length(btrim(coalesce(p_source_key,''))) not between 2 and 120
  or length(btrim(coalesce(p_ingestion_run_id,''))) not between 8 and 160
  or p_window_start is null or p_window_end<=p_window_start or p_max_source_updated_at is null
  or p_max_source_updated_at>now()+interval '5 minutes'
  or p_observed_count<0 or (p_expected_count is not null and (p_expected_count<0 or p_observed_count>p_expected_count)) then
  raise exception using errcode='22023',message='INVALID_BI_SOURCE_WATERMARK';
 end if;
 v_status:=case when p_expected_count is not null and p_observed_count=p_expected_count then 'complete' else 'partial' end;
 select * into v from public.bi_source_watermarks where tenant_id=p_tenant_id and source_key=p_source_key
  and source_window_start=p_window_start and source_window_end=p_window_end and ingestion_run_id=p_ingestion_run_id for update;
 if found then
  if v.max_source_updated_at<>p_max_source_updated_at or v.expected_record_count is distinct from p_expected_count
   or v.observed_record_count<>p_observed_count or v.status<>v_status then
   raise exception using errcode='23505',message='BI_WATERMARK_IDEMPOTENCY_COLLISION';
  end if;
  return jsonb_build_object('status','duplicate','watermark_id',v.id,'watermark_status',v.status);
 end if;
 insert into public.bi_source_watermarks(tenant_id,source_key,source_window_start,source_window_end,
  max_source_updated_at,expected_record_count,observed_record_count,ingestion_run_id,status)
 values(p_tenant_id,p_source_key,p_window_start,p_window_end,p_max_source_updated_at,
  p_expected_count,p_observed_count,p_ingestion_run_id,v_status) returning * into v;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'bi.source_watermark.recorded','bi_source_watermark',v.id::text,
  jsonb_build_object('tenant_id',p_tenant_id,'source_key',p_source_key,'status',v.status,'ingestion_run_id',p_ingestion_run_id));
 return jsonb_build_object('status','recorded','watermark_id',v.id,'watermark_status',v.status);
end $$;
revoke all on function public.bi_record_source_watermark(uuid,text,timestamptz,timestamptz,timestamptz,bigint,bigint,text,uuid) from public,anon,authenticated;
grant execute on function public.bi_record_source_watermark(uuid,text,timestamptz,timestamptz,timestamptz,bigint,bigint,text,uuid) to service_role;

create or replace function public.bi_create_reconciliation_run(
 p_tenant_id uuid,p_period_start date,p_period_end date,p_source_domain text,p_source_reference text,
 p_expected_total numeric,p_observed_total numeric,p_tolerance numeric,p_idempotency_key text,p_actor_user_id uuid
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v public.bi_reconciliation_runs%rowtype;
begin
 if p_period_end<p_period_start or length(btrim(coalesce(p_source_domain,''))) not between 2 and 80
  or length(btrim(coalesce(p_source_reference,'')))<8 or p_expected_total<0 or p_observed_total<0
  or p_tolerance<0 or length(coalesce(p_idempotency_key,'')) not between 8 and 120 then
  raise exception using errcode='22023',message='INVALID_BI_RECONCILIATION_RUN';
 end if;
 select * into v from public.bi_reconciliation_runs where tenant_id=p_tenant_id and idempotency_key=p_idempotency_key for update;
 if found then
  if v.period_start<>p_period_start or v.period_end<>p_period_end or v.source_domain<>p_source_domain
   or v.source_reference<>p_source_reference or v.expected_total<>p_expected_total
   or v.observed_total<>p_observed_total or v.tolerance<>p_tolerance then
   raise exception using errcode='23505',message='BI_RECONCILIATION_IDEMPOTENCY_COLLISION';
  end if;
  return jsonb_build_object('status','duplicate','reconciliation_id',v.id,'reconciliation_status',v.status);
 end if;
 insert into public.bi_reconciliation_runs(tenant_id,period_start,period_end,source_domain,source_reference,
  expected_total,observed_total,tolerance,status,created_by,idempotency_key)
 values(p_tenant_id,p_period_start,p_period_end,p_source_domain,p_source_reference,p_expected_total,
  p_observed_total,p_tolerance,'pending',p_actor_user_id,p_idempotency_key) returning * into v;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'bi.reconciliation.created','bi_reconciliation_run',v.id::text,
  jsonb_build_object('tenant_id',p_tenant_id,'source_domain',p_source_domain,'period_start',p_period_start,'period_end',p_period_end));
 return jsonb_build_object('status','created','reconciliation_id',v.id,'reconciliation_status',v.status,'variance',v.variance);
end $$;
revoke all on function public.bi_create_reconciliation_run(uuid,date,date,text,text,numeric,numeric,numeric,text,uuid) from public,anon,authenticated;
grant execute on function public.bi_create_reconciliation_run(uuid,date,date,text,text,numeric,numeric,numeric,text,uuid) to service_role;

create or replace function public.bi_review_reconciliation_run(
 p_reconciliation_id uuid,p_decision text,p_waiver_reason text,p_actor_user_id uuid
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v public.bi_reconciliation_runs%rowtype;
begin
 if p_decision not in ('passed','failed','waived') then
  raise exception using errcode='22023',message='INVALID_BI_RECONCILIATION_DECISION';
 end if;
 select * into v from public.bi_reconciliation_runs where id=p_reconciliation_id for update;
 if not found then raise exception using errcode='P0002',message='BI_RECONCILIATION_NOT_FOUND'; end if;
 if v.status<>'pending' then raise exception using errcode='23514',message='BI_RECONCILIATION_ALREADY_REVIEWED'; end if;
 if v.created_by is null or v.created_by=p_actor_user_id then
  raise exception using errcode='42501',message='INDEPENDENT_BI_RECONCILIATION_REVIEWER_REQUIRED';
 end if;
 if p_decision='passed' and abs(v.variance)>v.tolerance then
  raise exception using errcode='23514',message='BI_RECONCILIATION_VARIANCE_EXCEEDS_TOLERANCE';
 end if;
 if p_decision='waived' and length(btrim(coalesce(p_waiver_reason,'')))<10 then
  raise exception using errcode='22023',message='BI_RECONCILIATION_WAIVER_REASON_REQUIRED';
 end if;
 update public.bi_reconciliation_runs set status=p_decision,reviewed_by=p_actor_user_id,reviewed_at=now(),
  waiver_reason=case when p_decision='waived' then p_waiver_reason else null end
 where id=p_reconciliation_id returning * into v;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'bi.reconciliation.'||p_decision,'bi_reconciliation_run',v.id::text,
  jsonb_build_object('tenant_id',v.tenant_id,'variance',v.variance,'tolerance',v.tolerance,'source_domain',v.source_domain));
 return jsonb_build_object('reconciliation_id',v.id,'status',v.status,'variance',v.variance,'reviewed_by',v.reviewed_by);
end $$;
revoke all on function public.bi_review_reconciliation_run(uuid,text,text,uuid) from public,anon,authenticated;
grant execute on function public.bi_review_reconciliation_run(uuid,text,text,uuid) to service_role;

create or replace function public.bi_register_metric_source_lineage(
 p_metric_id uuid,p_formula_version integer,p_source_entity text,p_source_field text,p_source_key text,
 p_join_rule text,p_aggregation_rule text,p_transformation_reference text,p_actor_user_id uuid
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v public.bi_metric_definitions%rowtype; l record;
begin
 select * into v from public.bi_metric_definitions where id=p_metric_id for share;
 if not found or not v.active or v.formula_version<>p_formula_version then
  raise exception using errcode='23514',message='BI_METRIC_FORMULA_VERSION_INACTIVE';
 end if;
 if not p_source_entity=any(v.source_entities) or length(btrim(coalesce(p_source_field,'')))<1
  or length(btrim(coalesce(p_source_key,'')))<1 or length(btrim(coalesce(p_join_rule,'')))<3
  or length(btrim(coalesce(p_aggregation_rule,'')))<3 or length(btrim(coalesce(p_transformation_reference,'')))<3 then
  raise exception using errcode='22023',message='INVALID_BI_METRIC_SOURCE_LINEAGE';
 end if;
 if p_actor_user_id=v.created_by then raise exception using errcode='42501',message='INDEPENDENT_BI_LINEAGE_APPROVER_REQUIRED'; end if;
 select * into l from public.bi_metric_source_lineage where metric_id=p_metric_id and formula_version=p_formula_version
  and source_entity=p_source_entity and source_field=p_source_field and source_key=p_source_key for update;
 if found then
  if l.join_rule<>p_join_rule or l.aggregation_rule<>p_aggregation_rule or l.transformation_reference<>p_transformation_reference then
   raise exception using errcode='23505',message='BI_LINEAGE_IDEMPOTENCY_COLLISION';
  end if;
  return jsonb_build_object('status','duplicate','lineage_id',l.id);
 end if;
 insert into public.bi_metric_source_lineage(metric_id,formula_version,source_entity,source_field,source_key,
  join_rule,aggregation_rule,transformation_reference,approved_by,approved_at)
 values(p_metric_id,p_formula_version,p_source_entity,p_source_field,p_source_key,p_join_rule,
  p_aggregation_rule,p_transformation_reference,p_actor_user_id,now()) returning * into l;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'bi.metric_source_lineage.approved','bi_metric_source_lineage',l.id::text,
  jsonb_build_object('metric_id',p_metric_id,'formula_version',p_formula_version,'source_entity',p_source_entity));
 return jsonb_build_object('status','approved','lineage_id',l.id);
end $$;
revoke all on function public.bi_register_metric_source_lineage(uuid,integer,text,text,text,text,text,text,uuid) from public,anon,authenticated;
grant execute on function public.bi_register_metric_source_lineage(uuid,integer,text,text,text,text,text,text,uuid) to service_role;

create or replace function public.bi_create_metric_snapshot(
 p_tenant_id uuid,p_metric_id uuid,p_period_start timestamptz,p_period_end timestamptz,
 p_dimension_key text,p_dimension_value text,p_metric_value numeric,p_source_watermark_ids uuid[],
 p_reconciliation_run_ids uuid[],p_formula_version integer,p_idempotency_key text,p_actor_user_id uuid
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v public.bi_metric_snapshots%rowtype; m public.bi_metric_definitions%rowtype;
begin
 if p_period_end<=p_period_start or p_metric_value is null or
  length(btrim(coalesce(p_dimension_key,''))) not between 1 and 80 or
  length(btrim(coalesce(p_dimension_value,''))) not between 1 and 160 or
  coalesce(cardinality(p_source_watermark_ids),0)=0 or coalesce(cardinality(p_reconciliation_run_ids),0)=0 or
  length(coalesce(p_idempotency_key,'')) not between 8 and 120 then
  raise exception using errcode='22023',message='INVALID_BI_METRIC_SNAPSHOT';
 end if;
 select * into m from public.bi_metric_definitions where id=p_metric_id and active=true and formula_version=p_formula_version for share;
 if not found then raise exception using errcode='23514',message='BI_METRIC_FORMULA_VERSION_INACTIVE'; end if;
 select * into v from public.bi_metric_snapshots where tenant_id=p_tenant_id and idempotency_key=p_idempotency_key for update;
 if found then
  if v.metric_id<>p_metric_id or v.period_start<>p_period_start or v.period_end<>p_period_end
   or v.dimension_key<>p_dimension_key or v.dimension_value<>p_dimension_value
   or v.metric_value<>p_metric_value or v.source_watermark_ids<>p_source_watermark_ids
   or v.reconciliation_run_ids<>p_reconciliation_run_ids or v.formula_version<>p_formula_version then
   raise exception using errcode='23505',message='BI_SNAPSHOT_IDEMPOTENCY_COLLISION';
  end if;
  return jsonb_build_object('status','duplicate','snapshot_id',v.id,'snapshot_status',v.status);
 end if;
 insert into public.bi_metric_snapshots(tenant_id,metric_id,period_start,period_end,dimension_key,dimension_value,
  metric_value,source_watermark_ids,reconciliation_run_ids,formula_version,status,idempotency_key,created_by)
 values(p_tenant_id,p_metric_id,p_period_start,p_period_end,p_dimension_key,p_dimension_value,p_metric_value,
  p_source_watermark_ids,p_reconciliation_run_ids,p_formula_version,'draft',p_idempotency_key,p_actor_user_id)
 returning * into v;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'bi.metric_snapshot.created','bi_metric_snapshot',v.id::text,
  jsonb_build_object('tenant_id',p_tenant_id,'metric_id',p_metric_id,'formula_version',p_formula_version,'status',v.status));
 return jsonb_build_object('status','created','snapshot_id',v.id,'snapshot_status',v.status);
end $$;
revoke all on function public.bi_create_metric_snapshot(uuid,uuid,timestamptz,timestamptz,text,text,numeric,uuid[],uuid[],integer,text,uuid) from public,anon,authenticated;
grant execute on function public.bi_create_metric_snapshot(uuid,uuid,timestamptz,timestamptz,text,text,numeric,uuid[],uuid[],integer,text,uuid) to service_role;

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
