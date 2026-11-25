-- DESIGN DRAFT ONLY — NOT A MIGRATION.
-- Executive metrics consume only published BI snapshots. Alerts require evidence and independent verification.
create table if not exists public.executive_kpi_targets (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete restrict,
 metric_id uuid not null references public.bi_metric_definitions(id) on delete restrict,
 scope_type text not null check(scope_type in ('company','region','branch')),
 scope_key text not null,
 period_start date not null,
 period_end date not null,
 target_value numeric(24,6) not null,
 warning_threshold numeric(24,6) null,
 critical_threshold numeric(24,6) null,
 status text not null default 'draft' check(status in ('draft','active','expired','cancelled')),
 approved_by uuid null references auth.users(id) on delete restrict,
 approved_at timestamptz null,
 created_by uuid not null references auth.users(id) on delete restrict,
 created_at timestamptz not null default now(),
 unique(tenant_id,id),
 unique(tenant_id,metric_id,scope_type,scope_key,period_start,period_end),
 check(period_end>=period_start),
 check(status<>'active' or (approved_by is not null and approved_at is not null))
);
create table if not exists public.executive_operational_alerts (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete restrict,
 branch_id uuid null,
 alert_key text not null,
 severity text not null check(severity in ('info','warning','critical')),
 source_domain text not null,
 source_entity text not null,
 source_entity_id text not null,
 evidence_reference text not null,
 summary text not null,
 status text not null default 'open' check(status in ('open','acknowledged','investigating','resolved','dismissed')),
 assigned_to uuid null references auth.users(id) on delete restrict,
 resolved_by uuid null references auth.users(id) on delete restrict,
 resolved_at timestamptz null,
 resolution_note text null,
 verified_by uuid null references auth.users(id) on delete restrict,
 verified_at timestamptz null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(tenant_id,id),
 foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict,
 check(status<>'resolved' or (resolved_by is not null and resolved_at is not null and length(btrim(coalesce(resolution_note,'')))>=8)),
 check(verified_by is null or verified_by<>resolved_by),
 check(verified_at is null or verified_by is not null)
);
create index if not exists executive_alert_queue_idx on public.executive_operational_alerts(tenant_id,status,severity,created_at desc);
create table if not exists public.executive_alert_events (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete restrict,
 alert_id uuid not null,
 event_type text not null check(event_type in ('acknowledged','assigned','investigating','resolved','verified','reopened','dismissed')),
 actor_user_id uuid not null references auth.users(id) on delete restrict,
 note text null,
 evidence_reference text null,
 created_at timestamptz not null default now(),
 foreign key(tenant_id,alert_id) references public.executive_operational_alerts(tenant_id,id) on delete restrict
);
do $$
declare t text;
begin foreach t in array array['executive_kpi_targets','executive_operational_alerts','executive_alert_events'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('drop policy if exists service_role_only on public.%I',t);
 execute format('create policy service_role_only on public.%I for all to service_role using(true) with check(true)',t);
 execute format('revoke all on public.%I from anon,authenticated',t);
 execute format('grant select,insert,update,delete on public.%I to service_role',t);
end loop; end $$;
create or replace function public.executive_transition_alert(p_alert_id uuid,p_next_status text,p_actor_user_id uuid,p_note text,p_evidence_reference text)
returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v public.executive_operational_alerts%rowtype;
begin
 if p_next_status not in ('acknowledged','investigating','resolved','dismissed','open') then raise exception using errcode='22023',message='INVALID_EXECUTIVE_ALERT_STATUS'; end if;
 select * into v from public.executive_operational_alerts where id=p_alert_id for update;
 if not found then raise exception using errcode='P0002',message='EXECUTIVE_ALERT_NOT_FOUND'; end if;
 if v.status in ('resolved','dismissed') and p_next_status<>'open' then raise exception using errcode='23514',message='EXECUTIVE_ALERT_TERMINAL'; end if;
 if p_next_status='resolved' and (length(btrim(coalesce(p_note,'')))<8 or length(btrim(coalesce(p_evidence_reference,'')))<8) then
  raise exception using errcode='22023',message='EXECUTIVE_RESOLUTION_EVIDENCE_REQUIRED';
 end if;
 if p_next_status='open' and v.status not in ('resolved','dismissed') then raise exception using errcode='23514',message='EXECUTIVE_ALERT_NOT_REOPENABLE'; end if;
 update public.executive_operational_alerts set status=p_next_status,
  assigned_to=case when p_next_status in ('acknowledged','investigating','resolved') then coalesce(assigned_to,p_actor_user_id) else assigned_to end,
  resolved_by=case when p_next_status='resolved' then p_actor_user_id when p_next_status='open' then null else resolved_by end,
  resolved_at=case when p_next_status='resolved' then now() when p_next_status='open' then null else resolved_at end,
  resolution_note=case when p_next_status='resolved' then p_note when p_next_status='open' then null else resolution_note end,
  verified_by=case when p_next_status='open' then null else verified_by end,
  verified_at=case when p_next_status='open' then null else verified_at end,
  updated_at=now() where id=p_alert_id returning * into v;
 insert into public.executive_alert_events(tenant_id,alert_id,event_type,actor_user_id,note,evidence_reference)
 values(v.tenant_id,v.id,case when p_next_status='open' then 'reopened' else p_next_status end,p_actor_user_id,p_note,p_evidence_reference);
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'executive.alert.'||p_next_status,'executive_operational_alert',v.id::text,jsonb_build_object('tenant_id',v.tenant_id,'branch_id',v.branch_id,'evidence_reference',p_evidence_reference));
 return jsonb_build_object('alert_id',v.id,'status',v.status,'resolved_by',v.resolved_by);
end $$;
revoke all on function public.executive_transition_alert(uuid,text,uuid,text,text) from public,anon,authenticated;
grant execute on function public.executive_transition_alert(uuid,text,uuid,text,text) to service_role;

create or replace function public.executive_verify_alert(p_alert_id uuid,p_actor_user_id uuid,p_note text,p_evidence_reference text)
returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v public.executive_operational_alerts%rowtype;
begin
 select * into v from public.executive_operational_alerts where id=p_alert_id for update;
 if not found then raise exception using errcode='P0002',message='EXECUTIVE_ALERT_NOT_FOUND'; end if;
 if v.status<>'resolved' or v.resolved_by is null then raise exception using errcode='23514',message='EXECUTIVE_ALERT_NOT_RESOLVED'; end if;
 if v.resolved_by=p_actor_user_id then raise exception using errcode='42501',message='INDEPENDENT_VERIFIER_REQUIRED'; end if;
 if length(btrim(coalesce(p_note,'')))<8 or length(btrim(coalesce(p_evidence_reference,'')))<8 then raise exception using errcode='22023',message='VERIFICATION_EVIDENCE_REQUIRED'; end if;
 update public.executive_operational_alerts set verified_by=p_actor_user_id,verified_at=now(),updated_at=now() where id=p_alert_id;
 insert into public.executive_alert_events(tenant_id,alert_id,event_type,actor_user_id,note,evidence_reference)
 values(v.tenant_id,p_alert_id,'verified',p_actor_user_id,p_note,p_evidence_reference);
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'executive.alert.verified','executive_operational_alert',p_alert_id::text,jsonb_build_object('tenant_id',v.tenant_id,'resolved_by',v.resolved_by));
 return jsonb_build_object('alert_id',p_alert_id,'verified',true);
end $$;
revoke all on function public.executive_verify_alert(uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function public.executive_verify_alert(uuid,uuid,text,text) to service_role;
-- Every drilldown query must enforce the caller's tenant membership and branch assignments.
-- Published KPI snapshots and branch-level source transactions must share the same time window and reconciliation reference.


create table if not exists public.executive_branch_rankings (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete restrict,
 metric_id uuid not null references public.bi_metric_definitions(id) on delete restrict,
 period_start date not null,
 period_end date not null,
 branch_count integer not null check(branch_count between 1 and 150),
 status text not null default 'published' check(status in ('published','superseded')),
 source_snapshot_ids uuid[] not null,
 idempotency_key text not null check(length(btrim(idempotency_key)) between 8 and 160),
 published_by uuid not null references auth.users(id) on delete restrict,
 published_at timestamptz not null default now(),
 unique(tenant_id,id),
 unique(tenant_id,metric_id,period_start,period_end),
 unique(tenant_id,idempotency_key),
 check(period_end>=period_start),
 check(cardinality(source_snapshot_ids)=branch_count)
);
create table if not exists public.executive_branch_ranking_items (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete restrict,
 ranking_id uuid not null,
 branch_id uuid not null,
 rank_position integer not null check(rank_position between 1 and 150),
 metric_value numeric(24,6) not null,
 target_value numeric(24,6) not null,
 variance numeric(24,6) not null,
 snapshot_id uuid not null,
 created_at timestamptz not null default now(),
 unique(tenant_id,id),
 unique(tenant_id,ranking_id,branch_id),
 unique(tenant_id,ranking_id,rank_position),
 foreign key(tenant_id,ranking_id) references public.executive_branch_rankings(tenant_id,id) on delete restrict,
 foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict,
 foreign key(tenant_id,snapshot_id) references public.bi_metric_snapshots(tenant_id,id) on delete restrict
);
create index if not exists executive_branch_ranking_lookup_idx
 on public.executive_branch_ranking_items(tenant_id,ranking_id,rank_position);
do $$
declare t text;
begin foreach t in array array['executive_branch_rankings','executive_branch_ranking_items'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('drop policy if exists service_role_only on public.%I',t);
 execute format('create policy service_role_only on public.%I for all to service_role using(true) with check(true)',t);
 execute format('revoke all on public.%I from anon,authenticated',t);
 execute format('grant select,insert,update,delete on public.%I to service_role',t);
end loop; end $$;

-- Publish an immutable ranking only when every active branch has a fresh,
-- published, reconciled BI snapshot and an independently approved target.
create or replace function public.executive_publish_branch_ranking(
 p_tenant_id uuid,p_metric_id uuid,p_period_start date,p_period_end date,
 p_actor_user_id uuid,p_idempotency_key text
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v_count integer; v_ranking public.executive_branch_rankings%rowtype;
 v_prior public.executive_branch_rankings%rowtype; v_snapshot_ids uuid[];
begin
 if p_period_end<p_period_start or length(btrim(coalesce(p_idempotency_key,''))) not between 8 and 160 then
  raise exception using errcode='22023',message='INVALID_EXECUTIVE_RANKING_COMMAND';
 end if;
 perform 1 from public.tenants where id=p_tenant_id for update;
 if not found then raise exception using errcode='P0002',message='EXECUTIVE_TENANT_NOT_FOUND'; end if;
 select * into v_prior from public.executive_branch_rankings
  where tenant_id=p_tenant_id and idempotency_key=p_idempotency_key for update;
 if found then return jsonb_build_object('status','duplicate','ranking_id',v_prior.id,'branch_count',v_prior.branch_count); end if;
 select count(*) into v_count from public.branches where tenant_id=p_tenant_id and is_active=true;
 if v_count<1 or v_count>150 then raise exception using errcode='23514',message='EXECUTIVE_ACTIVE_BRANCH_COUNT_OUT_OF_RANGE'; end if;
 if exists(
  select 1 from public.branches b
  left join lateral (
   select s.id,s.metric_value from public.bi_metric_snapshots s
   where s.tenant_id=p_tenant_id and s.metric_id=p_metric_id
    and s.status='published' and s.dimension_key='branch' and s.dimension_value=b.id::text
    and s.period_start::date=p_period_start and s.period_end::date>=p_period_end
   order by s.published_at desc limit 1
  ) snap on true
  left join lateral (
   select t.id,t.target_value from public.executive_kpi_targets t
   where t.tenant_id=p_tenant_id and t.metric_id=p_metric_id and t.scope_type='branch'
    and t.scope_key=b.id::text and t.status='active'
    and t.period_start<=p_period_start and t.period_end>=p_period_end
   order by t.approved_at desc limit 1
  ) target on true
  where b.tenant_id=p_tenant_id and b.is_active=true
   and (snap.id is null or target.id is null)
 ) then raise exception using errcode='23514',message='EXECUTIVE_BRANCH_SNAPSHOT_OR_APPROVED_TARGET_MISSING'; end if;
 select array_agg(snap.id order by b.id) into v_snapshot_ids
 from public.branches b
 join lateral (
  select s.id from public.bi_metric_snapshots s
  where s.tenant_id=p_tenant_id and s.metric_id=p_metric_id
   and s.status='published' and s.dimension_key='branch' and s.dimension_value=b.id::text
   and s.period_start::date=p_period_start and s.period_end::date>=p_period_end
  order by s.published_at desc limit 1
 ) snap on true
 where b.tenant_id=p_tenant_id and b.is_active=true;
 insert into public.executive_branch_rankings(
  tenant_id,metric_id,period_start,period_end,branch_count,status,source_snapshot_ids,idempotency_key,published_by
 ) values(p_tenant_id,p_metric_id,p_period_start,p_period_end,v_count,'published',v_snapshot_ids,p_idempotency_key,p_actor_user_id)
 returning * into v_ranking;
 insert into public.executive_branch_ranking_items(
  tenant_id,ranking_id,branch_id,rank_position,metric_value,target_value,variance,snapshot_id
 )
 select p_tenant_id,v_ranking.id,b.id,
  row_number() over(order by snap.metric_value desc,b.id)::integer,
  snap.metric_value,target.target_value,snap.metric_value-target.target_value,snap.id
 from public.branches b
 join lateral (
  select s.id,s.metric_value from public.bi_metric_snapshots s
  where s.tenant_id=p_tenant_id and s.metric_id=p_metric_id and s.status='published'
   and s.dimension_key='branch' and s.dimension_value=b.id::text
   and s.period_start::date=p_period_start and s.period_end::date>=p_period_end
  order by s.published_at desc limit 1
 ) snap on true
 join lateral (
  select t.target_value from public.executive_kpi_targets t
  where t.tenant_id=p_tenant_id and t.metric_id=p_metric_id and t.scope_type='branch'
   and t.scope_key=b.id::text and t.status='active'
   and t.period_start<=p_period_start and t.period_end>=p_period_end
  order by t.approved_at desc limit 1
 ) target on true
 where b.tenant_id=p_tenant_id and b.is_active=true;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'executive.branch_ranking.published','executive_branch_rankings',v_ranking.id::text,
  jsonb_build_object('tenant_id',p_tenant_id,'metric_id',p_metric_id,'period_start',p_period_start,
   'period_end',p_period_end,'branch_count',v_count));
 return jsonb_build_object('status','published','ranking_id',v_ranking.id,'branch_count',v_count);
end $$;
revoke all on function public.executive_publish_branch_ranking(uuid,uuid,date,date,uuid,text) from public,anon,authenticated;
grant execute on function public.executive_publish_branch_ranking(uuid,uuid,date,date,uuid,text) to service_role;
