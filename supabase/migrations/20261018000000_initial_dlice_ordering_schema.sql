-- D'lice initial operational schema
-- Sensitive operational tables: no public/anon/authenticated access by default.
-- All writes must go through trusted server-side code with explicit validation.

create extension if not exists pgcrypto;

create table public.products (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  name text not null,
  description text,
  unit_price_idr integer check (unit_price_idr is null or unit_price_idr >= 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.product_capacity (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete restrict,
  service_date date not null,
  capacity integer not null check (capacity >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (product_id, service_date)
);

create table public.orders (
  id uuid primary key default gen_random_uuid(),
  order_number bigint generated always as identity unique,
  tracking_token_hash text unique,
  customer_name text not null,
  customer_whatsapp text not null,
  requested_date date not null,
  requested_time text not null,
  receiving_method text not null check (receiving_method in ('pickup', 'delivery')),
  delivery_address text,
  customer_notes text,
  product_subtotal_idr integer not null default 0 check (product_subtotal_idr >= 0),
  currency text not null default 'IDR' check (currency = 'IDR'),
  payment_status text not null default 'unpaid'
    check (payment_status in ('unpaid','pending_verification','paid','rejected','refunded')),
  operational_status text not null default 'received'
    check (operational_status in ('received','confirmed','preparing','ready_for_pickup','waiting_for_courier','in_delivery','completed','cancelled','delivery_issue')),
  timezone text not null default 'Asia/Makassar',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint delivery_address_required check (
    (receiving_method = 'delivery' and nullif(trim(delivery_address), '') is not null)
    or (receiving_method = 'pickup' and delivery_address is null)
  )
);

create table public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  product_id uuid references public.products(id) on delete restrict,
  product_name_snapshot text not null,
  quantity integer not null check (quantity between 1 and 100),
  unit_price_idr integer not null check (unit_price_idr >= 0),
  line_total_idr integer generated always as (quantity * unit_price_idr) stored,
  created_at timestamptz not null default now()
);

create table public.order_reservations (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete restrict,
  service_date date not null,
  quantity integer not null check (quantity between 1 and 100),
  status text not null default 'active'
    check (status in ('active','held_for_verification','consumed','released','expired')),
  expires_at timestamptz not null default (now() + interval '15 minutes'),
  payment_declared_at timestamptz,
  proof_received_at timestamptz,
  released_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index order_reservations_capacity_idx
  on public.order_reservations (product_id, service_date, status, expires_at);

create table public.payment_records (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete restrict,
  method text not null check (method in ('bank_transfer','dlice_qris')),
  amount_idr integer not null check (amount_idr >= 0),
  status text not null default 'unpaid'
    check (status in ('unpaid','pending_verification','paid','rejected','refunded')),
  customer_reference text,
  proof_storage_path text,
  verified_by uuid references auth.users(id) on delete set null,
  verified_at timestamptz,
  admin_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.order_status_history (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  status_type text not null check (status_type in ('payment','operational','reservation')),
  old_status text,
  new_status text not null,
  changed_by uuid references auth.users(id) on delete set null,
  note text,
  created_at timestamptz not null default now()
);

create table public.admin_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('sales_admin','owner')),
  display_name text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.admin_audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_user_id uuid references auth.users(id) on delete set null,
  action text not null,
  entity_type text not null,
  entity_id text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table public.payment_settings (
  id uuid primary key default gen_random_uuid(),
  method text not null unique check (method in ('bank_transfer','dlice_qris')),
  display_name text not null,
  instructions text,
  account_name text,
  account_number text,
  qr_storage_path text,
  is_enabled boolean not null default false,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger products_set_updated_at before update on public.products
for each row execute function public.set_updated_at();
create trigger product_capacity_set_updated_at before update on public.product_capacity
for each row execute function public.set_updated_at();
create trigger orders_set_updated_at before update on public.orders
for each row execute function public.set_updated_at();
create trigger order_reservations_set_updated_at before update on public.order_reservations
for each row execute function public.set_updated_at();
create trigger payment_records_set_updated_at before update on public.payment_records
for each row execute function public.set_updated_at();
create trigger admin_profiles_set_updated_at before update on public.admin_profiles
for each row execute function public.set_updated_at();
create trigger payment_settings_set_updated_at before update on public.payment_settings
for each row execute function public.set_updated_at();

alter table public.products enable row level security;
alter table public.product_capacity enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.order_reservations enable row level security;
alter table public.payment_records enable row level security;
alter table public.order_status_history enable row level security;
alter table public.admin_profiles enable row level security;
alter table public.admin_audit_logs enable row level security;
alter table public.payment_settings enable row level security;

revoke all on public.products, public.product_capacity, public.orders, public.order_items,
  public.order_reservations, public.payment_records, public.order_status_history,
  public.admin_profiles, public.admin_audit_logs, public.payment_settings from anon, authenticated;

grant all on public.products, public.product_capacity, public.orders, public.order_items,
  public.order_reservations, public.payment_records, public.order_status_history,
  public.admin_profiles, public.admin_audit_logs, public.payment_settings to service_role;
grant usage, select on all sequences in schema public to service_role;

comment on table public.orders is 'Private order records; access only through trusted server-side operations.';
comment on table public.order_reservations is 'Capacity reservations; checkout holds expire after 15 minutes unless payment/proof is declared in time.';
comment on table public.admin_audit_logs is 'Administrative actions; writes must be server-side.';
