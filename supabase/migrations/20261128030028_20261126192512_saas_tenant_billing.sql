-- D'Lice FnB OS official migration generated from reviewed domain SQL drafts.
-- Source files:
--   docs/implementation/sql/SAAS_TENANT_BILLING_SCHEMA_DRAFT.sql

create table if not exists public.saas_plan_versions (
 id uuid primary key default gen_random_uuid(),
 plan_key text not null,
 version integer not null check(version>0),
 display_name text not null,
 billing_interval text not null check(billing_interval in ('monthly','annual')),
 price_idr bigint not null check(price_idr>=0),
 currency text not null default 'IDR' check(currency='IDR'),
 effective_from date not null,
 effective_to date null,
 active boolean not null default true,
 approved_by uuid not null references auth.users(id) on delete restrict,
 approved_at timestamptz not null,
 created_at timestamptz not null default now(),
 unique(plan_key,version),
 check(effective_to is null or effective_to>=effective_from)
);
create table if not exists public.saas_plan_entitlements (
 id uuid primary key default gen_random_uuid(),
 plan_version_id uuid not null references public.saas_plan_versions(id) on delete restrict,
 entitlement_key text not null,
 limit_value bigint null check(limit_value is null or limit_value>=0),
 enabled boolean not null default true,
 unit text not null,
 created_at timestamptz not null default now(),
 unique(plan_version_id,entitlement_key)
);
create table if not exists public.saas_tenant_subscriptions (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete restrict,
 plan_version_id uuid not null references public.saas_plan_versions(id) on delete restrict,
 status text not null default 'trialing' check(status in ('trialing','active','past_due','suspended','cancelled','expired')),
 starts_at timestamptz not null,
 current_period_start timestamptz not null,
 current_period_end timestamptz not null,
 trial_ends_at timestamptz null,
 grace_ends_at timestamptz null,
 cancelled_at timestamptz null,
 created_by uuid not null references auth.users(id) on delete restrict,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(tenant_id,id),
 check(current_period_end>current_period_start)
);
create unique index if not exists saas_one_live_subscription_per_tenant
 on public.saas_tenant_subscriptions(tenant_id)
 where status in ('trialing','active','past_due','suspended');
create table if not exists public.saas_usage_events (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete restrict,
 entitlement_key text not null,
 quantity bigint not null check(quantity>0),
 occurred_at timestamptz not null,
 source_entity text not null,
 source_id text not null,
 idempotency_key text not null,
 metadata jsonb not null default '{}',
 created_at timestamptz not null default now(),
 unique(tenant_id,idempotency_key),
 unique(tenant_id,entitlement_key,source_entity,source_id)
);
create index if not exists saas_usage_period_idx on public.saas_usage_events(tenant_id,entitlement_key,occurred_at);
create table if not exists public.saas_invoices (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete restrict,
 subscription_id uuid not null,
 invoice_number text not null,
 period_start date not null,
 period_end date not null,
 subtotal_idr bigint not null check(subtotal_idr>=0),
 tax_idr bigint not null default 0 check(tax_idr>=0),
 total_idr bigint generated always as (subtotal_idr+tax_idr) stored,
 status text not null default 'draft' check(status in ('draft','issued','partially_paid','paid','void','overdue')),
 issued_at timestamptz null,
 due_at timestamptz null,
 paid_at timestamptz null,
 idempotency_key text not null,
 created_at timestamptz not null default now(),
 unique(tenant_id,id),
 unique(tenant_id,invoice_number),
 unique(tenant_id,idempotency_key),
 foreign key(tenant_id,subscription_id) references public.saas_tenant_subscriptions(tenant_id,id) on delete restrict,
 check(period_end>=period_start),
 check(status<>'issued' or (issued_at is not null and due_at is not null)),
 check(status<>'paid' or paid_at is not null)
);
create table if not exists public.saas_invoice_payments (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete restrict,
 invoice_id uuid not null,
 provider text not null,
 provider_reference text not null,
 amount_idr bigint not null check(amount_idr>0),
 status text not null check(status in ('pending','succeeded','failed','refunded')),
 settled_at timestamptz null,
 created_at timestamptz not null default now(),
 unique(tenant_id,id),
 unique(tenant_id,provider,provider_reference),
 foreign key(tenant_id,invoice_id) references public.saas_invoices(tenant_id,id) on delete restrict,
 check(status<>'succeeded' or settled_at is not null)
);
create table if not exists public.saas_tenant_offboarding_requests (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete restrict,
 status text not null default 'requested' check(status in ('requested','approved','blocked','processing','completed','cancelled')),
 reason text not null check(length(btrim(reason)) between 8 and 1000),
 legal_hold boolean not null default false,
 legal_hold_reference text null,
 requested_by uuid not null references auth.users(id) on delete restrict,
 approved_by uuid null references auth.users(id) on delete restrict,
 approved_at timestamptz null,
 retention_until timestamptz null,
 completed_at timestamptz null,
 completion_evidence text null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(tenant_id,id),
 check(not legal_hold or length(btrim(coalesce(legal_hold_reference,'')))>=8),
 check(status not in ('approved','processing','completed') or (approved_by is not null and approved_at is not null and retention_until is not null)),
 check(status<>'completed' or (completed_at is not null and length(btrim(coalesce(completion_evidence,'')))>=8)),
 check(approved_by is null or approved_by<>requested_by)
);
create unique index if not exists saas_one_open_offboarding_per_tenant
 on public.saas_tenant_offboarding_requests(tenant_id) where status in ('requested','approved','blocked','processing');
do $$
declare t text;
begin foreach t in array array['saas_plan_versions','saas_plan_entitlements','saas_tenant_subscriptions','saas_usage_events','saas_invoices','saas_invoice_payments','saas_tenant_offboarding_requests'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('drop policy if exists service_role_only on public.%I',t);
 execute format('create policy service_role_only on public.%I for all to service_role using(true) with check(true)',t);
 execute format('revoke all on public.%I from anon,authenticated',t);
 execute format('grant select,insert,update,delete on public.%I to service_role',t);
end loop; end $$;
create or replace function public.saas_check_entitlement(p_tenant_id uuid,p_entitlement_key text,p_quantity bigint,p_at timestamptz)
returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v_subscription public.saas_tenant_subscriptions%rowtype; v_limit bigint; v_enabled boolean; v_used bigint;
begin
 if p_quantity<=0 then raise exception using errcode='22023',message='INVALID_USAGE_QUANTITY'; end if;
 select * into v_subscription from public.saas_tenant_subscriptions where tenant_id=p_tenant_id and status in ('trialing','active','past_due')
  and current_period_start<=p_at and current_period_end>p_at
  and (status<>'trialing' or trial_ends_at is null or trial_ends_at>p_at)
  and (status<>'past_due' or grace_ends_at is not null and grace_ends_at>p_at)
  order by created_at desc limit 1 for update;
 if not found then return jsonb_build_object('allowed',false,'reason','NO_ACTIVE_SUBSCRIPTION'); end if;
 select enabled,limit_value into v_enabled,v_limit from public.saas_plan_entitlements where plan_version_id=v_subscription.plan_version_id and entitlement_key=p_entitlement_key;
 if not found or not v_enabled then return jsonb_build_object('allowed',false,'reason','ENTITLEMENT_DISABLED'); end if;
 select coalesce(sum(quantity),0) into v_used from public.saas_usage_events where tenant_id=p_tenant_id and entitlement_key=p_entitlement_key
  and occurred_at>=v_subscription.current_period_start and occurred_at<v_subscription.current_period_end;
 if v_limit is not null and v_used+p_quantity>v_limit then return jsonb_build_object('allowed',false,'reason','QUOTA_EXCEEDED','used',v_used,'limit',v_limit); end if;
 return jsonb_build_object('allowed',true,'used',v_used,'limit',v_limit,'subscription_id',v_subscription.id);
end $$;
revoke all on function public.saas_check_entitlement(uuid,text,bigint,timestamptz) from public,anon,authenticated;
grant execute on function public.saas_check_entitlement(uuid,text,bigint,timestamptz) to service_role;

create or replace function public.saas_approve_offboarding(p_request_id uuid,p_actor_user_id uuid,p_retention_days integer,p_legal_hold boolean,p_legal_hold_reference text)
returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v public.saas_tenant_offboarding_requests%rowtype;
begin
 if p_retention_days<30 or p_retention_days>3650 then raise exception using errcode='22023',message='INVALID_RETENTION_PERIOD'; end if;
 select * into v from public.saas_tenant_offboarding_requests where id=p_request_id for update;
 if not found then raise exception using errcode='P0002',message='OFFBOARDING_REQUEST_NOT_FOUND'; end if;
 if v.status<>'requested' then raise exception using errcode='23514',message='OFFBOARDING_NOT_REQUESTED'; end if;
 if v.requested_by=p_actor_user_id then raise exception using errcode='42501',message='INDEPENDENT_OFFBOARDING_APPROVER_REQUIRED'; end if;
 if p_legal_hold and length(btrim(coalesce(p_legal_hold_reference,'')))<8 then raise exception using errcode='22023',message='LEGAL_HOLD_REFERENCE_REQUIRED'; end if;
 update public.saas_tenant_offboarding_requests set status=case when p_legal_hold then 'blocked' else 'approved' end,
  legal_hold=p_legal_hold,legal_hold_reference=case when p_legal_hold then p_legal_hold_reference else null end,
  approved_by=p_actor_user_id,approved_at=now(),retention_until=now()+make_interval(days=>p_retention_days),updated_at=now()
 where id=p_request_id returning * into v;
 if not p_legal_hold then
  update public.saas_tenant_subscriptions set status='suspended',updated_at=now()
   where tenant_id=v.tenant_id and status in ('trialing','active','past_due');
 end if;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'saas.tenant.offboarding.'||v.status,'saas_tenant_offboarding_request',v.id::text,
  jsonb_build_object('tenant_id',v.tenant_id,'retention_until',v.retention_until,'legal_hold',v.legal_hold));
 return jsonb_build_object('request_id',v.id,'status',v.status,'retention_until',v.retention_until);
end $$;
revoke all on function public.saas_approve_offboarding(uuid,uuid,integer,boolean,text) from public,anon,authenticated;
grant execute on function public.saas_approve_offboarding(uuid,uuid,integer,boolean,text) to service_role;

-- Entitlement check RPC must lock/read active subscription and aggregate current-period usage.
-- Tenant suspension/offboarding must preserve audit and retention/legal-hold requirements.

-- Harden usage metering for retry-safe server-side event ingestion.
-- A retry with identical facts returns the original event even if the plan
-- has since changed; reusing a key with different facts is rejected.
create or replace function public.saas_record_usage(
 p_tenant_id uuid,p_entitlement_key text,p_quantity bigint,p_source_entity text,p_source_id text,
 p_idempotency_key text,p_metadata jsonb,p_at timestamptz
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v_check jsonb; v_event public.saas_usage_events%rowtype;
begin
 if p_tenant_id is null or length(btrim(coalesce(p_entitlement_key,''))) not between 2 and 100
  or p_quantity<=0 or length(btrim(coalesce(p_source_entity,''))) not between 2 and 80
  or length(btrim(coalesce(p_source_id,''))) not between 1 and 160
  or length(btrim(coalesce(p_idempotency_key,''))) not between 8 and 160
  or p_at is null or octet_length(coalesce(p_metadata,'{}')::text)>8192 then
  raise exception using errcode='22023',message='INVALID_USAGE_EVENT';
 end if;
 perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text,0));
 select * into v_event from public.saas_usage_events
  where tenant_id=p_tenant_id and idempotency_key=p_idempotency_key;
 if found then
  if v_event.entitlement_key<>p_entitlement_key or v_event.quantity<>p_quantity
   or v_event.source_entity<>p_source_entity or v_event.source_id<>p_source_id or v_event.occurred_at<>p_at then
   raise exception using errcode='23505',message='USAGE_IDEMPOTENCY_KEY_PAYLOAD_MISMATCH';
  end if;
  return jsonb_build_object('usage_event_id',v_event.id,'quantity',v_event.quantity,
   'entitlement_key',v_event.entitlement_key,'duplicate',true);
 end if;
 v_check:=public.saas_check_entitlement(p_tenant_id,p_entitlement_key,p_quantity,p_at);
 if coalesce((v_check->>'allowed')::boolean,false)=false then
  raise exception using errcode='23514',message=coalesce(v_check->>'reason','ENTITLEMENT_DENIED');
 end if;
 insert into public.saas_usage_events(tenant_id,entitlement_key,quantity,occurred_at,source_entity,source_id,idempotency_key,metadata)
 values(p_tenant_id,p_entitlement_key,p_quantity,p_at,p_source_entity,p_source_id,p_idempotency_key,coalesce(p_metadata,'{}'))
 returning * into v_event;
 return jsonb_build_object('usage_event_id',v_event.id,'quantity',v_event.quantity,
  'entitlement_key',v_event.entitlement_key,'duplicate',false);
exception when unique_violation then
 raise exception using errcode='23505',message='USAGE_SOURCE_ALREADY_METERED_OR_IDEMPOTENCY_CONFLICT';
end $$;
revoke all on function public.saas_record_usage(uuid,text,bigint,text,text,text,jsonb,timestamptz) from public,anon,authenticated;
grant execute on function public.saas_record_usage(uuid,text,bigint,text,text,text,jsonb,timestamptz) to service_role;

-- Atomic subscription lifecycle, billing, payment settlement and usage metering.
alter table public.saas_tenant_offboarding_requests add column if not exists idempotency_key text null;
create unique index if not exists saas_offboarding_idempotency_uq
 on public.saas_tenant_offboarding_requests(tenant_id,idempotency_key) where idempotency_key is not null;
create unique index if not exists saas_invoice_period_uq
 on public.saas_invoices(tenant_id,subscription_id,period_start,period_end);

-- Revoke the legacy usage RPC without actor/audit context; use the audited overload below.
revoke all on function public.saas_record_usage(uuid,text,bigint,text,text,text,jsonb,timestamptz) from public,anon,authenticated,service_role;

create or replace function public.saas_record_usage(
 p_tenant_id uuid,p_entitlement_key text,p_quantity bigint,p_source_entity text,p_source_id text,
 p_idempotency_key text,p_metadata jsonb,p_at timestamptz,p_actor_user_id uuid
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v_check jsonb; v_event public.saas_usage_events%rowtype;
begin
 if p_tenant_id is null or length(btrim(coalesce(p_entitlement_key,''))) not between 2 and 100
  or p_quantity<=0 or length(btrim(coalesce(p_source_entity,''))) not between 2 and 80
  or length(btrim(coalesce(p_source_id,''))) not between 1 and 160
  or length(btrim(coalesce(p_idempotency_key,''))) not between 8 and 160
  or p_at is null or p_actor_user_id is null or octet_length(coalesce(p_metadata,'{}')::text)>8192 then
  raise exception using errcode='22023',message='INVALID_USAGE_EVENT';
 end if;
 perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text,0));
 select * into v_event from public.saas_usage_events where tenant_id=p_tenant_id and idempotency_key=p_idempotency_key;
 if found then
  if v_event.entitlement_key<>p_entitlement_key or v_event.quantity<>p_quantity
   or v_event.source_entity<>p_source_entity or v_event.source_id<>p_source_id
   or v_event.occurred_at<>p_at or v_event.metadata is distinct from coalesce(p_metadata,'{}') then
   raise exception using errcode='23505',message='USAGE_IDEMPOTENCY_KEY_PAYLOAD_MISMATCH';
  end if;
  return jsonb_build_object('usage_event_id',v_event.id,'quantity',v_event.quantity,
   'entitlement_key',v_event.entitlement_key,'duplicate',true);
 end if;
 v_check:=public.saas_check_entitlement(p_tenant_id,p_entitlement_key,p_quantity,p_at);
 if coalesce((v_check->>'allowed')::boolean,false)=false then
  raise exception using errcode='23514',message=coalesce(v_check->>'reason','ENTITLEMENT_DENIED');
 end if;
 insert into public.saas_usage_events(tenant_id,entitlement_key,quantity,occurred_at,source_entity,source_id,idempotency_key,metadata)
 values(p_tenant_id,p_entitlement_key,p_quantity,p_at,p_source_entity,p_source_id,p_idempotency_key,coalesce(p_metadata,'{}'))
 returning * into v_event;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'saas.usage.recorded','saas_usage_event',v_event.id::text,
  jsonb_build_object('tenant_id',p_tenant_id,'entitlement_key',p_entitlement_key,'quantity',p_quantity,
   'source_entity',p_source_entity,'source_id',p_source_id));
 return jsonb_build_object('usage_event_id',v_event.id,'quantity',v_event.quantity,
  'entitlement_key',v_event.entitlement_key,'duplicate',false);
exception when unique_violation then
 raise exception using errcode='23505',message='USAGE_SOURCE_ALREADY_METERED_OR_IDEMPOTENCY_CONFLICT';
end $$;
revoke all on function public.saas_record_usage(uuid,text,bigint,text,text,text,jsonb,timestamptz,uuid) from public,anon,authenticated;
grant execute on function public.saas_record_usage(uuid,text,bigint,text,text,text,jsonb,timestamptz,uuid) to service_role;

create or replace function public.saas_start_trial(
 p_tenant_id uuid,p_plan_version_id uuid,p_trial_days integer,p_actor_user_id uuid
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v_plan public.saas_plan_versions%rowtype; v_sub public.saas_tenant_subscriptions%rowtype;
 v_now timestamptz:=now(); v_end timestamptz;
begin
 if p_trial_days not between 1 and 60 then raise exception using errcode='22023',message='INVALID_TRIAL_DURATION'; end if;
 select * into v_plan from public.saas_plan_versions where id=p_plan_version_id and active=true
  and effective_from<=current_date and (effective_to is null or effective_to>=current_date) for share;
 if not found then raise exception using errcode='23514',message='SAAS_PLAN_NOT_EFFECTIVE'; end if;
 if exists(select 1 from public.saas_tenant_subscriptions where tenant_id=p_tenant_id and status in ('trialing','active','past_due','suspended')) then
  raise exception using errcode='23505',message='SAAS_LIVE_SUBSCRIPTION_ALREADY_EXISTS';
 end if;
 v_end:=v_now+make_interval(days=>p_trial_days);
 insert into public.saas_tenant_subscriptions(tenant_id,plan_version_id,status,starts_at,current_period_start,current_period_end,trial_ends_at,created_by)
 values(p_tenant_id,p_plan_version_id,'trialing',v_now,v_now,v_end,v_end,p_actor_user_id) returning * into v_sub;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'saas.subscription.trial_started','saas_tenant_subscription',v_sub.id::text,
  jsonb_build_object('tenant_id',p_tenant_id,'plan_version_id',p_plan_version_id,'trial_days',p_trial_days));
 return jsonb_build_object('subscription_id',v_sub.id,'status',v_sub.status,'trial_ends_at',v_sub.trial_ends_at);
end $$;
revoke all on function public.saas_start_trial(uuid,uuid,integer,uuid) from public,anon,authenticated;
grant execute on function public.saas_start_trial(uuid,uuid,integer,uuid) to service_role;

create or replace function public.saas_cancel_subscription(
 p_tenant_id uuid,p_subscription_id uuid,p_reason text,p_actor_user_id uuid
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v public.saas_tenant_subscriptions%rowtype;
begin
 if length(btrim(coalesce(p_reason,'')))<8 then raise exception using errcode='22023',message='SAAS_CANCELLATION_REASON_REQUIRED'; end if;
 select * into v from public.saas_tenant_subscriptions where tenant_id=p_tenant_id and id=p_subscription_id for update;
 if not found then raise exception using errcode='P0002',message='SAAS_SUBSCRIPTION_NOT_FOUND'; end if;
 if v.status='cancelled' then return jsonb_build_object('status','duplicate','subscription_id',v.id); end if;
 if v.status not in ('trialing','active','past_due','suspended') then
  raise exception using errcode='23514',message='SAAS_SUBSCRIPTION_NOT_CANCELLABLE';
 end if;
 update public.saas_tenant_subscriptions set status='cancelled',cancelled_at=now(),updated_at=now() where id=v.id returning * into v;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'saas.subscription.cancelled','saas_tenant_subscription',v.id::text,
  jsonb_build_object('tenant_id',p_tenant_id,'reason',left(p_reason,500)));
 return jsonb_build_object('subscription_id',v.id,'status',v.status,'cancelled_at',v.cancelled_at);
end $$;
revoke all on function public.saas_cancel_subscription(uuid,uuid,text,uuid) from public,anon,authenticated;
grant execute on function public.saas_cancel_subscription(uuid,uuid,text,uuid) to service_role;

create or replace function public.saas_request_offboarding(
 p_tenant_id uuid,p_reason text,p_idempotency_key text,p_actor_user_id uuid
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v public.saas_tenant_offboarding_requests%rowtype;
begin
 if length(btrim(coalesce(p_reason,''))) not between 8 and 1000 or
  length(btrim(coalesce(p_idempotency_key,''))) not between 8 and 120 then
  raise exception using errcode='22023',message='INVALID_SAAS_OFFBOARDING_REQUEST';
 end if;
 select * into v from public.saas_tenant_offboarding_requests where tenant_id=p_tenant_id and idempotency_key=p_idempotency_key for update;
 if found then
  if v.reason<>p_reason then raise exception using errcode='23505',message='SAAS_OFFBOARDING_IDEMPOTENCY_COLLISION'; end if;
  return jsonb_build_object('status','duplicate','request_id',v.id,'request_status',v.status);
 end if;
 insert into public.saas_tenant_offboarding_requests(tenant_id,reason,requested_by,idempotency_key)
 values(p_tenant_id,p_reason,p_actor_user_id,p_idempotency_key) returning * into v;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'saas.tenant.offboarding.requested','saas_tenant_offboarding_request',v.id::text,
  jsonb_build_object('tenant_id',p_tenant_id));
 return jsonb_build_object('request_id',v.id,'status',v.status);
end $$;
revoke all on function public.saas_request_offboarding(uuid,text,text,uuid) from public,anon,authenticated;
grant execute on function public.saas_request_offboarding(uuid,text,text,uuid) to service_role;

create or replace function public.saas_issue_invoice(
 p_tenant_id uuid,p_subscription_id uuid,p_period_start date,p_period_end date,
 p_tax_idr bigint,p_due_at timestamptz,p_idempotency_key text,p_actor_user_id uuid
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v_sub public.saas_tenant_subscriptions%rowtype; v_plan public.saas_plan_versions%rowtype;
 v_invoice public.saas_invoices%rowtype; v_number text; v_next_start timestamptz; v_next_end timestamptz;
begin
 if p_period_end<p_period_start or p_tax_idr<0 or p_due_at<=now()
  or length(coalesce(p_idempotency_key,'')) not between 8 and 120 then
  raise exception using errcode='22023',message='INVALID_SAAS_INVOICE';
 end if;
 select * into v_invoice from public.saas_invoices where tenant_id=p_tenant_id and idempotency_key=p_idempotency_key for update;
 if found then return jsonb_build_object('status','duplicate','invoice_id',v_invoice.id,'invoice_status',v_invoice.status); end if;
 select * into v_sub from public.saas_tenant_subscriptions where tenant_id=p_tenant_id and id=p_subscription_id for update;
 if not found then raise exception using errcode='23514',message='SAAS_BILLABLE_SUBSCRIPTION_PERIOD_REQUIRED'; end if;
 select * into v_plan from public.saas_plan_versions where id=v_sub.plan_version_id;
 if not found then raise exception using errcode='23514',message='SAAS_PLAN_VERSION_NOT_FOUND'; end if;
 if v_sub.status='trialing' then
  if v_sub.trial_ends_at is null or v_sub.trial_ends_at>now() then
   raise exception using errcode='23514',message='SAAS_TRIAL_NOT_EXPIRED';
  end if;
  v_next_start:=v_sub.trial_ends_at;
  v_next_end:=case when v_plan.billing_interval='annual' then v_next_start+interval '1 year' else v_next_start+interval '1 month' end;
  update public.saas_tenant_subscriptions set status='past_due',current_period_start=v_next_start,
   current_period_end=v_next_end,grace_ends_at=now()+interval '7 days',updated_at=now()
   where id=v_sub.id returning * into v_sub;
 elsif v_sub.status='active' and v_sub.current_period_end<=now() then
  v_next_start:=v_sub.current_period_end;
  v_next_end:=case when v_plan.billing_interval='annual' then v_next_start+interval '1 year' else v_next_start+interval '1 month' end;
  update public.saas_tenant_subscriptions set status='past_due',current_period_start=v_next_start,
   current_period_end=v_next_end,grace_ends_at=now()+interval '7 days',updated_at=now()
   where id=v_sub.id returning * into v_sub;
 end if;
 if v_sub.status not in ('active','past_due') or
  v_sub.current_period_start::date<>p_period_start or v_sub.current_period_end::date<>p_period_end then
  raise exception using errcode='23514',message='SAAS_BILLABLE_SUBSCRIPTION_PERIOD_REQUIRED';
 end if;
 v_number:='SAAS-'||to_char(p_period_start,'YYYYMM')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,8));
 insert into public.saas_invoices(tenant_id,subscription_id,invoice_number,period_start,period_end,subtotal_idr,tax_idr,
  status,issued_at,due_at,idempotency_key)
 values(p_tenant_id,p_subscription_id,v_number,p_period_start,p_period_end,v_plan.price_idr,p_tax_idr,
  'issued',now(),p_due_at,p_idempotency_key) returning * into v_invoice;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'saas.invoice.issued','saas_invoice',v_invoice.id::text,
  jsonb_build_object('tenant_id',p_tenant_id,'subscription_id',p_subscription_id,'invoice_number',v_number,'total_idr',v_invoice.total_idr));
 return jsonb_build_object('invoice_id',v_invoice.id,'invoice_number',v_invoice.invoice_number,'status',v_invoice.status,'total_idr',v_invoice.total_idr,'due_at',v_invoice.due_at);
end $$;
revoke all on function public.saas_issue_invoice(uuid,uuid,date,date,bigint,timestamptz,text,uuid) from public,anon,authenticated;
grant execute on function public.saas_issue_invoice(uuid,uuid,date,date,bigint,timestamptz,text,uuid) to service_role;

create or replace function public.saas_record_invoice_payment(
 p_tenant_id uuid,p_invoice_id uuid,p_provider text,p_provider_reference text,p_amount_idr bigint,
 p_status text,p_settled_at timestamptz,p_actor_user_id uuid
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v_invoice public.saas_invoices%rowtype; v_payment public.saas_invoice_payments%rowtype;
 v_paid bigint; v_next_status text;
begin
 if length(btrim(coalesce(p_provider,''))) not between 2 and 80 or
  length(btrim(coalesce(p_provider_reference,''))) not between 2 and 160 or p_amount_idr<=0 or
  p_status not in ('pending','succeeded','failed') or
  (p_status='succeeded' and p_settled_at is null) then
  raise exception using errcode='22023',message='INVALID_SAAS_INVOICE_PAYMENT';
 end if;
 select * into v_invoice from public.saas_invoices where tenant_id=p_tenant_id and id=p_invoice_id for update;
 if not found then raise exception using errcode='P0002',message='SAAS_INVOICE_NOT_FOUND'; end if;
 select * into v_payment from public.saas_invoice_payments where tenant_id=p_tenant_id and provider=p_provider and provider_reference=p_provider_reference for update;
 if found then
  if v_payment.invoice_id<>p_invoice_id or v_payment.amount_idr<>p_amount_idr then
   raise exception using errcode='23505',message='SAAS_PAYMENT_PROVIDER_REFERENCE_COLLISION';
  end if;
  if v_payment.status=p_status then
   return jsonb_build_object('status','duplicate','payment_id',v_payment.id,'invoice_status',v_invoice.status);
  end if;
  if v_payment.status<>'pending' or p_status not in ('succeeded','failed') then
   raise exception using errcode='23505',message='SAAS_PAYMENT_STATUS_TRANSITION_INVALID';
  end if;
  update public.saas_invoice_payments set status=p_status,settled_at=p_settled_at where id=v_payment.id returning * into v_payment;
 else
  if v_invoice.status in ('void','paid') then raise exception using errcode='23514',message='SAAS_INVOICE_NOT_PAYABLE'; end if;
  insert into public.saas_invoice_payments(tenant_id,invoice_id,provider,provider_reference,amount_idr,status,settled_at)
  values(p_tenant_id,p_invoice_id,p_provider,p_provider_reference,p_amount_idr,p_status,p_settled_at) returning * into v_payment;
 end if;
 select coalesce(sum(amount_idr),0) into v_paid from public.saas_invoice_payments
  where tenant_id=p_tenant_id and invoice_id=p_invoice_id and status='succeeded';
 if v_paid>v_invoice.total_idr then raise exception using errcode='23514',message='SAAS_INVOICE_OVERPAYMENT'; end if;
 v_next_status:=case when v_paid=v_invoice.total_idr then 'paid' when v_paid>0 then 'partially_paid' else v_invoice.status end;
 update public.saas_invoices set status=v_next_status,paid_at=case when v_next_status='paid' then now() else null end
  where id=p_invoice_id returning * into v_invoice;
 if v_next_status='paid' then
  update public.saas_tenant_subscriptions set status='active',grace_ends_at=null,updated_at=now()
   where tenant_id=p_tenant_id and id=v_invoice.subscription_id and status in ('past_due','suspended');
 end if;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'saas.invoice.payment.'||p_status,'saas_invoice_payment',v_payment.id::text,
  jsonb_build_object('tenant_id',p_tenant_id,'invoice_id',p_invoice_id,'amount_idr',p_amount_idr,'invoice_paid_idr',v_paid,'invoice_status',v_invoice.status));
 return jsonb_build_object('payment_id',v_payment.id,'invoice_id',p_invoice_id,'invoice_status',v_invoice.status,'paid_idr',v_paid,'total_idr',v_invoice.total_idr);
end $$;
revoke all on function public.saas_record_invoice_payment(uuid,uuid,text,text,bigint,text,timestamptz,uuid) from public,anon,authenticated;
grant execute on function public.saas_record_invoice_payment(uuid,uuid,text,text,bigint,text,timestamptz,uuid) to service_role;

create or replace function public.saas_complete_offboarding(
 p_request_id uuid,p_actor_user_id uuid,p_completion_evidence text
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v public.saas_tenant_offboarding_requests%rowtype;
begin
 select * into v from public.saas_tenant_offboarding_requests where id=p_request_id for update;
 if not found then raise exception using errcode='P0002',message='OFFBOARDING_REQUEST_NOT_FOUND'; end if;
 if v.status<>'approved' or v.legal_hold or v.retention_until is null or v.retention_until>now() then
  raise exception using errcode='23514',message='SAAS_OFFBOARDING_RETENTION_OR_LEGAL_HOLD_BLOCKED';
 end if;
 if p_actor_user_id in (v.requested_by,v.approved_by) or length(btrim(coalesce(p_completion_evidence,'')))<8 then
  raise exception using errcode='42501',message='INDEPENDENT_OFFBOARDING_COMPLETER_AND_EVIDENCE_REQUIRED';
 end if;
 update public.saas_tenant_offboarding_requests set status='completed',completed_at=now(),
  completion_evidence=p_completion_evidence,updated_at=now() where id=v.id returning * into v;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'saas.tenant.offboarding.completed','saas_tenant_offboarding_request',v.id::text,
  jsonb_build_object('tenant_id',v.tenant_id,'retention_until',v.retention_until,'evidence',p_completion_evidence));
 return jsonb_build_object('request_id',v.id,'status',v.status,'completed_at',v.completed_at);
end $$;
revoke all on function public.saas_complete_offboarding(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.saas_complete_offboarding(uuid,uuid,text) to service_role;
