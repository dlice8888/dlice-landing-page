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
-- Entitlement check RPC must lock/read active subscription and aggregate current-period usage.
-- Tenant suspension/offboarding must preserve audit and retention/legal-hold requirements.
