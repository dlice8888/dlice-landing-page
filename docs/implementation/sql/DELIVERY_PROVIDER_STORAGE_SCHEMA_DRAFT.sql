-- DESIGN DRAFT ONLY — NOT A MIGRATION.
-- Provider contracts and the private Storage bucket must be approved/configured separately.

create table if not exists public.delivery_provider_quotes (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  branch_id uuid not null,
  source_type text not null check(source_type in ('online_order','pos_sale')),
  source_id uuid not null,
  provider_id text not null,
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
  unique(tenant_id,provider_id,provider_quote_id),
  foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict
);
create index if not exists delivery_quotes_source_idx
  on public.delivery_provider_quotes(tenant_id,source_type,source_id,expires_at desc);

create table if not exists public.delivery_dispatches (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  branch_id uuid not null,
  source_type text not null check(source_type in ('online_order','pos_sale')),
  source_id uuid not null,
  quote_id uuid not null,
  provider_id text not null,
  provider_booking_reference text null,
  status text not null default 'booking_pending' check(status in ('booking_pending','booked','picked_up','in_transit','delivered','failed','cancelled','compensation_pending','compensated')),
  cod_expected_idr bigint not null default 0 check(cod_expected_idr>=0),
  cod_collected_idr bigint null check(cod_collected_idr is null or cod_collected_idr>=0),
  courier_cost_expected_idr bigint not null check(courier_cost_expected_idr>=0),
  courier_cost_final_idr bigint null check(courier_cost_final_idr is null or courier_cost_final_idr>=0),
  idempotency_key text not null check(length(idempotency_key) between 8 and 160),
  created_by uuid not null references auth.users(id) on delete restrict,
  booked_at timestamptz null,
  delivered_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tenant_id,id),
  unique(tenant_id,source_type,source_id),
  unique(tenant_id,idempotency_key),
  unique(provider_id,provider_booking_reference),
  foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict,
  foreign key(tenant_id,quote_id) references public.delivery_provider_quotes(tenant_id,id) on delete restrict
);
create index if not exists delivery_dispatch_queue_idx
  on public.delivery_dispatches(tenant_id,branch_id,status,created_at desc);

create table if not exists public.delivery_provider_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  dispatch_id uuid not null,
  provider_id text not null,
  provider_event_id text not null,
  event_type text not null,
  resulting_status text not null,
  payload_sha256 text not null check(payload_sha256 ~ '^[0-9a-f]{64}$'),
  occurred_at timestamptz not null,
  received_at timestamptz not null default now(),
  payload jsonb not null check(jsonb_typeof(payload)='object'),
  unique(tenant_id,id),
  unique(provider_id,provider_event_id),
  foreign key(tenant_id,dispatch_id) references public.delivery_dispatches(tenant_id,id) on delete restrict
);

create table if not exists public.delivery_storage_evidence (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  branch_id uuid not null,
  dispatch_id uuid not null,
  evidence_type text not null check(evidence_type in ('pickup_photo','delivery_photo','recipient_signature','exception_photo')),
  bucket_id text not null check(bucket_id='delivery-private'),
  object_path text not null,
  content_type text not null check(content_type in ('image/jpeg','image/png','application/pdf')),
  size_bytes bigint not null check(size_bytes>0 and size_bytes<=15728640),
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
  cod_expected_idr bigint not null check(cod_expected_idr>=0),
  cod_collected_idr bigint not null check(cod_collected_idr>=0),
  cod_remitted_idr bigint not null check(cod_remitted_idr>=0),
  courier_cost_expected_idr bigint not null check(courier_cost_expected_idr>=0),
  courier_cost_final_idr bigint not null check(courier_cost_final_idr>=0),
  finance_source_reconciliation_id uuid not null,
  status text not null check(status in ('reconciled','exception')),
  evidence_sha256 text not null check(evidence_sha256 ~ '^[0-9a-f]{64}$'),
  reconciled_by uuid null references auth.users(id) on delete restrict,
  reconciled_at timestamptz null,
  unique(tenant_id,id),
  unique(tenant_id,dispatch_id),
  foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict,
  foreign key(tenant_id,dispatch_id) references public.delivery_dispatches(tenant_id,id) on delete restrict,
  check((status='reconciled' and cod_collected_idr=cod_remitted_idr and reconciled_by is not null and reconciled_at is not null) or status<>'reconciled')
);

create table if not exists public.delivery_outbox (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  dispatch_id uuid not null,
  event_type text not null check(event_type in ('book','cancel','compensate','refresh_status')),
  status text not null default 'queued' check(status in ('queued','claimed','completed','retry','dead_letter')),
  attempts integer not null default 0 check(attempts>=0),
  next_attempt_at timestamptz not null default now(),
  idempotency_key text not null,
  last_error_code text null,
  created_at timestamptz not null default now(),
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
    'delivery_provider_quotes','delivery_dispatches','delivery_provider_events',
    'delivery_storage_evidence','delivery_cost_reconciliations','delivery_outbox'
  ] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('drop policy if exists service_role_only on public.%I',t);
    execute format('create policy service_role_only on public.%I for all to service_role using (true) with check (true)',t);
    execute format('revoke all on public.%I from anon, authenticated',t);
    execute format('grant select,insert,update,delete on public.%I to service_role',t);
  end loop;
end $$;

-- Storage bucket delivery-private must be private. Client upload is not granted.
-- Edge Function uploads only after authorization and writes immutable metadata above.
