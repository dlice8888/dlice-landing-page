-- DESIGN DRAFT ONLY — NOT A MIGRATION.
-- Compatible extension of DELIVERY_FULFILLMENT_SCHEMA_DRAFT.sql.
-- Do not recreate delivery_dispatches or delivery_provider_events: those tables
-- already exist in the baseline draft with order_id/provider/status columns.
-- Provider secrets remain in Supabase secrets; only a secret reference is stored.

create table if not exists public.delivery_provider_configs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  branch_id uuid null,
  provider_key text not null check(length(btrim(provider_key)) between 2 and 60),
  display_name text not null check(length(btrim(display_name)) between 2 and 100),
  credential_secret_reference text not null check(length(btrim(credential_secret_reference)) between 3 and 120),
  integration_mode text not null default 'manual' check(integration_mode in ('manual','api')),
  status text not null default 'pending' check(status in ('pending','active','suspended','revoked')),
  approved_by uuid null references auth.users(id) on delete restrict,
  approved_at timestamptz null,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tenant_id,id),
  foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict,
  unique(tenant_id,branch_id,provider_key),
  check(status<>'active' or (approved_by is not null and approved_at is not null))
);
create index if not exists delivery_provider_configs_active_idx
  on public.delivery_provider_configs(tenant_id,branch_id,status);

create table if not exists public.delivery_provider_quotes (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  branch_id uuid not null,
  order_id uuid not null references public.orders(id) on delete restrict,
  provider_config_id uuid not null,
  provider_quote_id text not null,
  service_level text not null,
  currency text not null default 'IDR' check(currency='IDR'),
  quoted_cost_idr bigint not null check(quoted_cost_idr>=0),
  cod_supported boolean not null default false,
  expires_at timestamptz not null,
  provider_payload_sha256 text not null check(provider_payload_sha256 ~ '^[0-9a-f]{64}$'),
  status text not null default 'quoted' check(status in ('quoted','selected','expired','rejected')),
  created_at timestamptz not null default now(),
  unique(tenant_id,id),
  unique(tenant_id,provider_config_id,provider_quote_id),
  foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict,
  foreign key(tenant_id,provider_config_id) references public.delivery_provider_configs(tenant_id,id) on delete restrict
);
create index if not exists delivery_quotes_order_idx
  on public.delivery_provider_quotes(tenant_id,order_id,expires_at desc,status);

-- Extend the baseline dispatch model without changing its established order/status
-- lifecycle. The existing provider/provider_service and cod_amount_idr columns
-- remain the compatibility source for current ERP actions.
alter table public.delivery_dispatches
  add column if not exists quote_id uuid null,
  add column if not exists provider_booking_reference text null,
  add column if not exists cod_collected_idr bigint null check(cod_collected_idr is null or cod_collected_idr>=0),
  add column if not exists cod_remitted_idr bigint null check(cod_remitted_idr is null or cod_remitted_idr>=0),
  add column if not exists courier_cost_expected_idr bigint null check(courier_cost_expected_idr is null or courier_cost_expected_idr>=0),
  add column if not exists courier_cost_final_idr bigint null check(courier_cost_final_idr is null or courier_cost_final_idr>=0);

do $$
begin
  if not exists(select 1 from pg_constraint where conname='delivery_dispatch_quote_fk') then
    alter table public.delivery_dispatches add constraint delivery_dispatch_quote_fk
      foreign key(tenant_id,quote_id) references public.delivery_provider_quotes(tenant_id,id) on delete restrict;
  end if;
end $$;
create unique index if not exists delivery_dispatch_provider_booking_reference_uq
  on public.delivery_dispatches(tenant_id,provider,provider_booking_reference)
  where provider_booking_reference is not null;

-- Keep the baseline provider-event identity/dedupe columns; add evidence that
-- the raw provider signature was verified before an event was applied.
alter table public.delivery_provider_events
  add column if not exists signature_verified_at timestamptz null,
  add column if not exists signature_key_version text null;

create table if not exists public.delivery_storage_evidence (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  branch_id uuid not null,
  dispatch_id uuid not null,
  evidence_type text not null check(evidence_type in ('pickup_photo','delivery_photo','recipient_signature','exception_photo')),
  bucket_id text not null check(bucket_id='delivery-proof'),
  object_path text not null,
  content_type text not null check(content_type in ('image/jpeg','image/png','image/webp')),
  size_bytes bigint not null check(size_bytes>0 and size_bytes<=5242880),
  sha256 text not null check(sha256 ~ '^[0-9a-f]{64}$'),
  uploaded_by uuid not null references auth.users(id) on delete restrict,
  uploaded_at timestamptz not null default now(),
  unique(tenant_id,id),
  unique(bucket_id,object_path),
  foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict,
  foreign key(tenant_id,dispatch_id) references public.delivery_dispatches(tenant_id,id) on delete restrict,
  check(object_path like tenant_id::text||'/'||branch_id::text||'/'||dispatch_id::text||'/%')
);

create table if not exists public.delivery_cost_reconciliations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  branch_id uuid not null,
  dispatch_id uuid not null,
  customer_fee_idr bigint not null check(customer_fee_idr>=0),
  merchant_subsidy_idr bigint not null check(merchant_subsidy_idr>=0),
  cod_expected_idr bigint not null check(cod_expected_idr>=0),
  cod_collected_idr bigint not null check(cod_collected_idr>=0),
  cod_remitted_idr bigint not null check(cod_remitted_idr>=0),
  courier_cost_expected_idr bigint not null check(courier_cost_expected_idr>=0),
  courier_cost_final_idr bigint not null check(courier_cost_final_idr>=0),
  provider_settlement_idr bigint not null check(provider_settlement_idr>=0),
  provider_fee_idr bigint not null check(provider_fee_idr>=0),
  finance_source_reconciliation_id uuid not null,
  status text not null check(status in ('reconciled','exception')),
  evidence_sha256 text not null check(evidence_sha256 ~ '^[0-9a-f]{64}$'),
  reconciled_by uuid null references auth.users(id) on delete restrict,
  reconciled_at timestamptz null,
  unique(tenant_id,id),
  unique(tenant_id,dispatch_id),
  foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict,
  foreign key(tenant_id,dispatch_id) references public.delivery_dispatches(tenant_id,id) on delete restrict,
  check(cod_remitted_idr<=cod_collected_idr),
  check(status<>'reconciled' or (
    cod_collected_idr=cod_remitted_idr and
    courier_cost_final_idr=customer_fee_idr+merchant_subsidy_idr and
    provider_settlement_idr=courier_cost_final_idr-provider_fee_idr and
    reconciled_by is not null and reconciled_at is not null
  ))
);

create table if not exists public.delivery_outbox (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  dispatch_id uuid not null,
  event_type text not null check(event_type in ('book','cancel','compensate','refresh_status')),
  status text not null default 'queued' check(status in ('queued','claimed','completed','retry','dead_letter')),
  attempts integer not null default 0 check(attempts>=0),
  next_attempt_at timestamptz not null default now(),
  idempotency_key text not null check(length(btrim(idempotency_key)) between 8 and 160),
  last_error_code text null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tenant_id,id),
  unique(tenant_id,idempotency_key),
  foreign key(tenant_id,dispatch_id) references public.delivery_dispatches(tenant_id,id) on delete restrict
);
create index if not exists delivery_outbox_due_idx
  on public.delivery_outbox(status,next_attempt_at) where status in ('queued','retry');

do $$
declare t text;
begin
  foreach t in array array[
    'delivery_provider_configs','delivery_provider_quotes',
    'delivery_storage_evidence','delivery_cost_reconciliations','delivery_outbox'
  ] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('drop policy if exists service_role_only on public.%I',t);
    execute format('create policy service_role_only on public.%I for all to service_role using (true) with check (true)',t);
    execute format('revoke all on public.%I from anon, authenticated',t);
    execute format('grant select,insert,update,delete on public.%I to service_role',t);
  end loop;
end $$;

-- The existing delivery-proof bucket must be PRIVATE. No client upload policy
-- is granted; the Edge Function verifies actor/branch, file signature, size,
-- hashes the bytes and records immutable metadata after server-side upload.
