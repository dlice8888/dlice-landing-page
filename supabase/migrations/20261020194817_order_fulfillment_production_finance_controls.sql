-- D'Lice order routing, receiving, recipe/production and finance controls.
-- Applied to staging only; migration version 20261020194817.
alter table public.branches
  add column if not exists latitude numeric(9,6),
  add column if not exists longitude numeric(9,6),
  add column if not exists service_radius_km numeric(7,2) check (service_radius_km is null or service_radius_km >= 0),
  add column if not exists accepts_online_orders boolean not null default false,
  add column if not exists pickup_enabled boolean not null default true,
  add column if not exists delivery_enabled boolean not null default false,
  add column if not exists daily_order_capacity integer check (daily_order_capacity is null or daily_order_capacity >= 0);
alter table public.orders
  add column if not exists branch_id uuid references public.branches(id) on delete restrict,
  add column if not exists branch_selection_source text check (branch_selection_source is null or branch_selection_source in ('ip_estimate','customer_choice','staff_assignment','legacy_unassigned')),
  add column if not exists fulfillment_status text not null default 'unassigned' check (fulfillment_status in ('unassigned','queued','accepted','preparing','ready','dispatched','fulfilled','failed','cancelled')),
  add column if not exists fulfillment_notes text,
  add column if not exists fulfilled_at timestamptz;
create index if not exists orders_branch_fulfillment_date_idx on public.orders(branch_id,requested_date,fulfillment_status);
alter table public.order_reservations add column if not exists branch_id uuid references public.branches(id) on delete restrict;
create index if not exists order_reservations_branch_date_status_idx on public.order_reservations(branch_id,service_date,status);
create table if not exists public.branch_product_capacity (
 id uuid primary key default gen_random_uuid(), branch_id uuid not null references public.branches(id) on delete restrict,
 product_id uuid not null references public.products(id) on delete restrict, service_date date not null,
 capacity integer not null check (capacity >= 0), reserved_quantity integer not null default 0 check (reserved_quantity >= 0),
 updated_at timestamptz not null default now(), unique(branch_id,product_id,service_date), check (reserved_quantity <= capacity));
create index if not exists branch_product_capacity_date_idx on public.branch_product_capacity(service_date,branch_id);
create table if not exists public.purchase_receipts (
 id uuid primary key default gen_random_uuid(), receipt_number text not null unique,
 purchase_order_id uuid not null references public.purchase_orders(id) on delete restrict,
 branch_id uuid not null references public.branches(id) on delete restrict,
 received_by uuid not null references public.admin_profiles(user_id) on delete restrict,
 status text not null default 'posted' check (status in ('posted','reversed')),
 supplier_delivery_reference text, notes text, received_at timestamptz not null default now(), created_at timestamptz not null default now());
create table if not exists public.purchase_receipt_items (
 id uuid primary key default gen_random_uuid(), receipt_id uuid not null references public.purchase_receipts(id) on delete restrict,
 purchase_order_item_id uuid not null references public.purchase_order_items(id) on delete restrict,
 inventory_item_id uuid not null references public.inventory_items(id) on delete restrict,
 quantity_received numeric(14,3) not null check (quantity_received > 0), unit_cost_idr bigint not null check (unit_cost_idr >= 0));
create index if not exists purchase_receipts_po_idx on public.purchase_receipts(purchase_order_id,received_at desc);
create table if not exists public.recipes (
 id uuid primary key default gen_random_uuid(), product_id uuid not null references public.products(id) on delete restrict,
 version integer not null check (version > 0), yield_quantity numeric(14,3) not null check (yield_quantity > 0),
 yield_unit text not null, status text not null default 'draft' check (status in ('draft','active','retired')),
 effective_from date not null default current_date, effective_to date, instructions text,
 created_by uuid references public.admin_profiles(user_id) on delete set null,
 approved_by uuid references public.admin_profiles(user_id) on delete set null, approved_at timestamptz,
 created_at timestamptz not null default now(), unique(product_id,version),
 check (effective_to is null or effective_to >= effective_from),
 check (status <> 'active' or (approved_by is not null and approved_at is not null)));
create unique index if not exists recipes_one_active_version_per_product on public.recipes(product_id) where status='active';
create table if not exists public.recipe_ingredients (
 id uuid primary key default gen_random_uuid(), recipe_id uuid not null references public.recipes(id) on delete cascade,
 inventory_item_id uuid not null references public.inventory_items(id) on delete restrict,
 quantity_per_yield numeric(14,4) not null check (quantity_per_yield > 0), unit text not null,
 is_optional boolean not null default false, unique(recipe_id,inventory_item_id));
create table if not exists public.production_batches (
 id uuid primary key default gen_random_uuid(), batch_number text not null unique,
 branch_id uuid not null references public.branches(id) on delete restrict,
 recipe_id uuid not null references public.recipes(id) on delete restrict,
 planned_quantity numeric(14,3) not null check (planned_quantity > 0),
 actual_good_quantity numeric(14,3) check (actual_good_quantity is null or actual_good_quantity >= 0),
 waste_quantity numeric(14,3) not null default 0 check (waste_quantity >= 0),
 status text not null default 'planned' check (status in ('planned','in_progress','completed','cancelled')),
 started_by uuid references public.admin_profiles(user_id) on delete set null,
 completed_by uuid references public.admin_profiles(user_id) on delete set null,
 started_at timestamptz, completed_at timestamptz, notes text, created_at timestamptz not null default now());
create table if not exists public.production_consumptions (
 id uuid primary key default gen_random_uuid(), batch_id uuid not null references public.production_batches(id) on delete restrict,
 inventory_item_id uuid not null references public.inventory_items(id) on delete restrict,
 planned_quantity numeric(14,3) not null check (planned_quantity >= 0),
 actual_quantity numeric(14,3) not null check (actual_quantity > 0), unit text not null,
 stock_movement_id uuid references public.stock_movements(id) on delete restrict,
 recorded_by uuid references public.admin_profiles(user_id) on delete set null,
 recorded_at timestamptz not null default now(), unique(batch_id,inventory_item_id));
create table if not exists public.payment_settlements (
 id uuid primary key default gen_random_uuid(), settlement_code text not null unique,
 payment_method text not null check (payment_method in ('bank_transfer','qris')), provider_reference text,
 settlement_date date not null, gross_amount_idr bigint not null check (gross_amount_idr >= 0),
 fee_amount_idr bigint not null default 0 check (fee_amount_idr >= 0),
 net_amount_idr bigint generated always as (gross_amount_idr-fee_amount_idr) stored,
 status text not null default 'pending' check (status in ('pending','matched','disputed','reversed')),
 received_amount_idr bigint check (received_amount_idr is null or received_amount_idr >= 0),
 reconciled_by uuid references public.admin_profiles(user_id) on delete set null, reconciled_at timestamptz, notes text,
 created_at timestamptz not null default now(), check (fee_amount_idr <= gross_amount_idr));
create table if not exists public.payment_settlement_items (
 id uuid primary key default gen_random_uuid(), settlement_id uuid not null references public.payment_settlements(id) on delete restrict,
 payment_record_id uuid references public.payment_records(id) on delete restrict,
 pos_sale_id uuid references public.pos_sales(id) on delete restrict, amount_idr bigint not null check (amount_idr >= 0),
 unique(settlement_id,payment_record_id), unique(settlement_id,pos_sale_id),
 check (payment_record_id is not null or pos_sale_id is not null));
create table if not exists public.refund_records (
 id uuid primary key default gen_random_uuid(), refund_code text not null unique,
 order_id uuid references public.orders(id) on delete restrict,
 payment_record_id uuid references public.payment_records(id) on delete restrict,
 pos_sale_id uuid references public.pos_sales(id) on delete restrict,
 branch_id uuid references public.branches(id) on delete restrict,
 amount_idr bigint not null check (amount_idr > 0), reason text not null,
 status text not null default 'requested' check (status in ('requested','approved','rejected','processed','failed')),
 requested_by uuid not null references public.admin_profiles(user_id) on delete restrict,
 reviewed_by uuid references public.admin_profiles(user_id) on delete restrict,
 processed_by uuid references public.admin_profiles(user_id) on delete restrict,
 external_reference text, requested_at timestamptz not null default now(), reviewed_at timestamptz, processed_at timestamptz,
 check (order_id is not null or payment_record_id is not null or pos_sale_id is not null));
create table if not exists public.cash_reconciliations (
 id uuid primary key default gen_random_uuid(), reconciliation_code text not null unique,
 branch_id uuid not null references public.branches(id) on delete restrict,
 shift_id uuid references public.pos_shifts(id) on delete restrict, business_date date not null,
 cash_expected_idr bigint not null default 0, cash_counted_idr bigint not null default 0,
 cash_variance_idr bigint generated always as (cash_counted_idr-cash_expected_idr) stored,
 bank_expected_idr bigint not null default 0, bank_received_idr bigint not null default 0,
 qris_expected_idr bigint not null default 0, qris_received_idr bigint not null default 0,
 status text not null default 'draft' check (status in ('draft','submitted','approved','exception')),
 prepared_by uuid not null references public.admin_profiles(user_id) on delete restrict,
 reviewed_by uuid references public.admin_profiles(user_id) on delete restrict, reviewed_at timestamptz, notes text,
 created_at timestamptz not null default now(), unique(branch_id,business_date,shift_id));
create table if not exists public.tax_settings (
 id uuid primary key default gen_random_uuid(), tax_code text not null unique, name text not null,
 rate numeric(7,4) not null check (rate >= 0 and rate <= 100), inclusive boolean not null default false,
 applies_to text not null default 'sales' check (applies_to in ('sales','purchase','both')),
 effective_from date not null, effective_to date, is_active boolean not null default true,
 created_by uuid references public.admin_profiles(user_id) on delete set null, created_at timestamptz not null default now(),
 check (effective_to is null or effective_to >= effective_from));
create table if not exists public.fiscal_periods (
 id uuid primary key default gen_random_uuid(), period_code text not null unique,
 starts_on date not null, ends_on date not null, status text not null default 'open' check (status in ('open','closing','closed','reopened')),
 closed_by uuid references public.admin_profiles(user_id) on delete set null, closed_at timestamptz,
 reopened_by uuid references public.admin_profiles(user_id) on delete set null, reopened_at timestamptz,
 closing_notes text, created_at timestamptz not null default now(), check (ends_on >= starts_on),
 check ((status='closed' and closed_at is not null) or status<>'closed'));
create table if not exists public.finance_journal_entries (
 id uuid primary key default gen_random_uuid(), entry_code text not null unique,
 fiscal_period_id uuid references public.fiscal_periods(id) on delete restrict,
 branch_id uuid references public.branches(id) on delete restrict, source_type text not null, source_id uuid,
 entry_date date not null, debit_account text not null, credit_account text not null,
 amount_idr bigint not null check (amount_idr > 0), description text not null,
 status text not null default 'posted' check (status in ('draft','posted','reversed')),
 reverses_entry_id uuid references public.finance_journal_entries(id) on delete restrict,
 created_by uuid references public.admin_profiles(user_id) on delete restrict, created_at timestamptz not null default now());
create index if not exists finance_journal_date_branch_idx on public.finance_journal_entries(entry_date,branch_id,status);
create index if not exists refund_records_status_date_idx on public.refund_records(status,requested_at desc);
do $$
declare t text;
begin
 foreach t in array array['branch_product_capacity','purchase_receipts','purchase_receipt_items','recipes','recipe_ingredients','production_batches','production_consumptions','payment_settlements','payment_settlement_items','refund_records','cash_reconciliations','tax_settings','fiscal_periods','finance_journal_entries'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('revoke all on table public.%I from anon, authenticated',t);
 end loop;
end $$;
