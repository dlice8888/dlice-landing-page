-- DESIGN DRAFT ONLY — NOT A MIGRATION.
-- Subscription and metering records extend existing tenants/memberships/integrations.
-- Entitlements must be enforced server-side; UI visibility is never authorization.
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
do $$
declare t text;
begin foreach t in array array['saas_plan_versions','saas_plan_entitlements','saas_tenant_subscriptions','saas_usage_events','saas_invoices','saas_invoice_payments'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('drop policy if exists service_role_only on public.%I',t);
 execute format('create policy service_role_only on public.%I for all to service_role using(true) with check(true)',t);
 execute format('revoke all on public.%I from anon,authenticated',t);
 execute format('grant select,insert,update,delete on public.%I to service_role',t);
end loop; end $$;
create or replace function public.saas_check_entitlement(p_tenant_id uuid,p_entitlement_key text,p_quantity bigint,p_at timestamptz)
returns jsonb language plpgsql security invoker set search_path=''
as $
declare v_subscription public.saas_tenant_subscriptions%rowtype; v_limit bigint; v_enabled boolean; v_used bigint;
begin
 if p_quantity<=0 then raise exception using errcode='22023',message='INVALID_USAGE_QUANTITY'; end if;
 select * into v_subscription from public.saas_tenant_subscriptions where tenant_id=p_tenant_id and status in ('trialing','active','past_due')
  and current_period_start<=p_at and current_period_end>p_at order by created_at desc limit 1 for update;
 if not found then return jsonb_build_object('allowed',false,'reason','NO_ACTIVE_SUBSCRIPTION'); end if;
 select enabled,limit_value into v_enabled,v_limit from public.saas_plan_entitlements where plan_version_id=v_subscription.plan_version_id and entitlement_key=p_entitlement_key;
 if not found or not v_enabled then return jsonb_build_object('allowed',false,'reason','ENTITLEMENT_DISABLED'); end if;
 select coalesce(sum(quantity),0) into v_used from public.saas_usage_events where tenant_id=p_tenant_id and entitlement_key=p_entitlement_key
  and occurred_at>=v_subscription.current_period_start and occurred_at<v_subscription.current_period_end;
 if v_limit is not null and v_used+p_quantity>v_limit then return jsonb_build_object('allowed',false,'reason','QUOTA_EXCEEDED','used',v_used,'limit',v_limit); end if;
 return jsonb_build_object('allowed',true,'used',v_used,'limit',v_limit,'subscription_id',v_subscription.id);
end $;
revoke all on function public.saas_check_entitlement(uuid,text,bigint,timestamptz) from public,anon,authenticated;
grant execute on function public.saas_check_entitlement(uuid,text,bigint,timestamptz) to service_role;

create or replace function public.saas_record_usage(p_tenant_id uuid,p_entitlement_key text,p_quantity bigint,p_source_entity text,p_source_id text,p_idempotency_key text,p_metadata jsonb,p_at timestamptz)
returns jsonb language plpgsql security invoker set search_path=''
as $
declare v_check jsonb; v_event public.saas_usage_events%rowtype;
begin
 perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||':'||p_entitlement_key,0));
 v_check:=public.saas_check_entitlement(p_tenant_id,p_entitlement_key,p_quantity,p_at);
 if coalesce((v_check->>'allowed')::boolean,false)=false then raise exception using errcode='23514',message=coalesce(v_check->>'reason','ENTITLEMENT_DENIED'); end if;
 insert into public.saas_usage_events(tenant_id,entitlement_key,quantity,occurred_at,source_entity,source_id,idempotency_key,metadata)
 values(p_tenant_id,p_entitlement_key,p_quantity,p_at,p_source_entity,p_source_id,p_idempotency_key,coalesce(p_metadata,'{}')) returning * into v_event;
 return jsonb_build_object('usage_event_id',v_event.id,'quantity',v_event.quantity,'entitlement_key',v_event.entitlement_key);
end $;
revoke all on function public.saas_record_usage(uuid,text,bigint,text,text,text,jsonb,timestamptz) from public,anon,authenticated;
grant execute on function public.saas_record_usage(uuid,text,bigint,text,text,text,jsonb,timestamptz) to service_role;

-- Entitlement check RPC must lock/read active subscription and aggregate current-period usage.
-- Tenant suspension/offboarding must preserve audit and retention/legal-hold requirements.
