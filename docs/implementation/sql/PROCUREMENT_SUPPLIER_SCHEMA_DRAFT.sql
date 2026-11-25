-- DESIGN DRAFT ONLY — NOT A MIGRATION.
-- Existing suppliers are global and have no tenant_id. This bridge makes ownership explicit.
-- A supplier may be shared only through an explicit reviewed tenant link; no implicit global access.
create table if not exists public.supplier_tenant_links (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete restrict,
 supplier_id uuid not null references public.suppliers(id) on delete restrict,
 status text not null default 'pending' check(status in ('pending','active','suspended','revoked')),
 relationship_type text not null default 'exclusive' check(relationship_type in ('exclusive','shared')),
 approved_by uuid null references auth.users(id) on delete restrict,
 approved_at timestamptz null,
 created_by uuid not null references auth.users(id) on delete restrict,
 created_at timestamptz not null default now(),
 unique(tenant_id,id),
 unique(tenant_id,supplier_id),
 check(status<>'active' or (approved_by is not null and approved_at is not null))
);
create table if not exists public.procurement_supplier_invoices (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete restrict,
 branch_id uuid not null,
 supplier_id uuid not null references public.suppliers(id) on delete restrict,
 purchase_order_id uuid not null references public.purchase_orders(id) on delete restrict,
 supplier_invoice_number text not null,
 invoice_date date not null,
 due_date date null,
 currency text not null default 'IDR' check(currency='IDR'),
 subtotal_idr bigint not null check(subtotal_idr>=0),
 tax_idr bigint not null default 0 check(tax_idr>=0),
 total_idr bigint generated always as (subtotal_idr+tax_idr) stored,
 status text not null default 'received' check(status in ('received','matching','matched','disputed','approved','posted','paid','void')),
 attachment_object_path text not null,
 idempotency_key text not null,
 received_by uuid not null references auth.users(id) on delete restrict,
 approved_by uuid null references auth.users(id) on delete restrict,
 posted_at timestamptz null,
 created_at timestamptz not null default now(),
 unique(tenant_id,id),
 unique(tenant_id,supplier_id,supplier_invoice_number),
 unique(tenant_id,idempotency_key),
 foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict,
 check(due_date is null or due_date>=invoice_date),
 check(status not in ('approved','posted','paid') or approved_by is not null),
 check(status<>'posted' or posted_at is not null)
);
create table if not exists public.procurement_invoice_match_lines (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete restrict,
 invoice_id uuid not null,
 purchase_order_item_id uuid not null references public.purchase_order_items(id) on delete restrict,
 receipt_item_id uuid not null references public.purchase_receipt_items(id) on delete restrict,
 invoiced_quantity numeric(14,3) not null check(invoiced_quantity>0),
 invoiced_unit_cost_idr bigint not null check(invoiced_unit_cost_idr>=0),
 received_quantity numeric(14,3) not null check(received_quantity>=0),
 ordered_quantity numeric(14,3) not null check(ordered_quantity>=0),
 quantity_variance numeric(14,3) generated always as (invoiced_quantity-received_quantity) stored,
 unit_cost_variance_idr bigint not null,
 match_status text not null check(match_status in ('matched','quantity_variance','price_variance','rejected')),
 reviewed_by uuid null references auth.users(id) on delete restrict,
 reviewed_at timestamptz null,
 created_at timestamptz not null default now(),
 foreign key(tenant_id,invoice_id) references public.procurement_supplier_invoices(tenant_id,id) on delete restrict,
 unique(tenant_id,id)
);
create index if not exists procurement_supplier_invoice_period_idx on public.procurement_supplier_invoices(tenant_id,branch_id,invoice_date,status);
create table if not exists public.procurement_approval_events (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete restrict,
 entity_type text not null check(entity_type in ('requisition','purchase_order','supplier_invoice')),
 entity_id uuid not null,
 event_type text not null check(event_type in ('submitted','approved','rejected','returned','posted')),
 actor_user_id uuid not null references auth.users(id) on delete restrict,
 reason text null,
 created_at timestamptz not null default now()
);
create index if not exists procurement_approval_entity_idx on public.procurement_approval_events(tenant_id,entity_type,entity_id,created_at);
do $$
declare t text;
begin foreach t in array array['supplier_tenant_links','procurement_supplier_invoices','procurement_invoice_match_lines','procurement_approval_events'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('drop policy if exists service_role_only on public.%I',t);
 execute format('create policy service_role_only on public.%I for all to service_role using(true) with check(true)',t);
 execute format('revoke all on public.%I from anon,authenticated',t);
 execute format('grant select,insert,update,delete on public.%I to service_role',t);
end loop; end $$;
-- Three-way matching must compare invoice lines to PO quantities/prices and accepted GRN lines.
-- Posting must be a single balanced Finance AP journal transaction with invoice reference.
-- Do not update suppliers directly from tenant-scoped endpoints until supplier_tenant_links is active.
