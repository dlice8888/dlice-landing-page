-- D'Lice multi-branch POS/ERP foundation. Staging only.
create extension if not exists pgcrypto;

create table if not exists public.branches (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code ~ '^[A-Z0-9-]{2,24}$'),
  name text not null,
  status text not null default 'planned' check (status in ('planned','active','suspended','closed')),
  address text,
  city text,
  province text,
  timezone text not null default 'Asia/Jakarta',
  opening_date date,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into public.branches (code,name,status,notes)
values ('DLC-HQ','D’Lice Head Office','active','Kantor pusat; lengkapi alamat sebelum operasional penuh.')
on conflict (code) do nothing;

insert into public.branches (code,name,status,notes)
select 'DLC-B' || lpad(n::text,3,'0'),
       'Slot Cabang ' || lpad(n::text,3,'0'),
       'planned',
       'Slot perencanaan; belum menjadi cabang aktif. Owner perlu menetapkan lokasi dan tanggal operasional.'
from generate_series(1,150) n
on conflict (code) do nothing;

create table if not exists public.job_positions (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  title text not null,
  department text not null,
  job_description text not null,
  default_permissions jsonb not null default '[]'::jsonb,
  recommended_headcount_per_branch numeric(6,2) not null default 0,
  is_head_office boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

insert into public.job_positions(code,title,department,job_description,default_permissions,recommended_headcount_per_branch,is_head_office) values
('owner','Owner / Direktur','Leadership','Menetapkan strategi, mengawasi KPI seluruh cabang, menyetujui kebijakan harga, anggaran, akses, dan keputusan risiko. Tidak menjalankan transaksi rutin sebagai default.','["branches","staff","settings","reports","finance","orders","catalog","inventory","procurement","pos","audit","hr"]',1,false),
('head_ops','Head of Operations','Operations','Memantau SLA pesanan, kapasitas produksi, kualitas, kepatuhan SOP, dan kinerja 150 cabang; melakukan eskalasi dan pembinaan manajer cabang.','["branches","reports","orders","inventory","procurement","pos","audit"]',1,true),
('area_manager','Area Manager','Operations','Mengawasi 5–10 cabang, audit stok dan layanan, menindaklanjuti KPI dan masalah cabang; hanya cabang yang ditugaskan.','["reports","orders","inventory","pos"]',0.15,true),
('branch_manager','Branch Manager','Branch Operations','Memimpin satu cabang, membuka/menutup operasional, menyetujui penyesuaian stok dan biaya sesuai batas, menyelesaikan keluhan dan rekonsiliasi kas.','["orders","catalog","inventory","procurement","pos","finance","reports","staff"]',1,false),
('shift_lead','Shift Leader','Branch Operations','Memimpin shift, serah terima kas, memeriksa kesiapan produksi, kualitas, kebersihan, dan penyelesaian pesanan.','["orders","inventory","pos","reports"]',1,false),
('cashier','Cashier / POS','Sales','Mencatat penjualan POS, menerima metode pembayaran yang disetujui, mencetak/menampilkan struk, menjaga kas, dan melakukan tutup shift.','["pos"]',2,false),
('kitchen_lead','Kitchen / Production Lead','Production','Mengatur batch produksi, resep dan standar mutu, prioritas order, hasil produksi, waste, serta kebutuhan bahan baku.','["orders","inventory","reports"]',1,false),
('kitchen_staff','Kitchen / Production Crew','Production','Menyiapkan produk sesuai SOP, mencatat hasil dan waste, menjaga kebersihan dan keselamatan pangan.','["orders","inventory"]',2,false),
('inventory_controller','Inventory Controller','Supply Chain','Menerima dan menghitung stok, mencatat pergerakan, stock opname, minimum stock, kedaluwarsa dan selisih.','["inventory","reports"]',0.5,false),
('procurement_officer','Procurement / Purchasing','Supply Chain','Mengelola vendor, permintaan pembelian, purchase order, perbandingan harga, penerimaan barang dan dokumen vendor.','["procurement","inventory","reports"]',0.25,true),
('finance_controller','Finance Controller','Finance','Merekonsiliasi penjualan, bank, biaya dan kas antar cabang; meninjau pengecualian dan menyiapkan laporan periodik.','["finance","reports","audit"]',0.2,true),
('finance_clerk','Finance Admin','Finance','Memeriksa bukti pembayaran, mencatat biaya, mengumpulkan dokumen dan menyiapkan rekonsiliasi; tidak menyetujui transaksi sendiri.','["finance","reports"]',0.5,true),
('customer_service','Customer Service','Customer Experience','Menangani pertanyaan, status order, komplain, refund request, dan tindak lanjut pelanggan dengan log yang dapat diaudit.','["orders","reports"]',1,false),
('delivery_coordinator','Delivery Coordinator','Fulfilment','Mengatur kurir dan rute, bukti serah terima, kegagalan pengantaran, dan status pesanan delivery.','["orders","reports"]',0.5,false),
('marketing','Marketing & CRM','Growth','Mengelola promosi, kalender kampanye, analisis funnel agregat, dan eksperimen peningkatan konversi tanpa mengakses data finansial sensitif.','["reports","catalog"]',0.25,true),
('hr_manager','HR / People Operations','People','Mengelola struktur jabatan, onboarding, pelatihan, penjadwalan tenaga kerja, dan evaluasi performa; tidak dapat menyetujui payroll sendiri.','["hr","staff","reports"]',0.15,true),
('internal_auditor','Internal Auditor','Governance','Melakukan pemeriksaan read-only terhadap jejak audit, transaksi, stok, biaya, dan pemisahan tugas; tidak mengubah transaksi yang diaudit.','["audit","reports"]',0.1,true)
on conflict (code) do nothing;

create table if not exists public.branch_assignments (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches(id) on delete restrict,
  user_id uuid not null references public.admin_profiles(user_id) on delete cascade,
  job_position_id uuid not null references public.job_positions(id) on delete restrict,
  employment_status text not null default 'active' check (employment_status in ('active','on_leave','inactive')),
  starts_on date not null default current_date,
  ends_on date,
  assigned_by uuid references public.admin_profiles(user_id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (branch_id,user_id,job_position_id),
  check (ends_on is null or ends_on >= starts_on)
);
create index if not exists branch_assignments_user_active_idx on public.branch_assignments(user_id,employment_status);
create index if not exists branch_assignments_branch_active_idx on public.branch_assignments(branch_id,employment_status);

create table if not exists public.inventory_items (
  id uuid primary key default gen_random_uuid(),
  sku text not null unique,
  name text not null,
  unit text not null default 'pcs',
  category text not null default 'ingredients',
  min_stock numeric(14,3) not null default 0 check (min_stock >= 0),
  is_active boolean not null default true,
  created_by uuid references public.admin_profiles(user_id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.branch_inventory (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches(id) on delete restrict,
  inventory_item_id uuid not null references public.inventory_items(id) on delete restrict,
  on_hand numeric(14,3) not null default 0,
  updated_at timestamptz not null default now(),
  unique(branch_id,inventory_item_id)
);
create index if not exists branch_inventory_branch_idx on public.branch_inventory(branch_id);
create table if not exists public.stock_movements (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches(id) on delete restrict,
  inventory_item_id uuid not null references public.inventory_items(id) on delete restrict,
  movement_type text not null check (movement_type in ('opening_balance','receipt','issue','adjustment_in','adjustment_out','transfer_in','transfer_out','waste')),
  quantity numeric(14,3) not null check (quantity > 0),
  reference_type text,
  reference_id uuid,
  notes text,
  created_by uuid references public.admin_profiles(user_id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists stock_movements_branch_created_idx on public.stock_movements(branch_id,created_at desc);
create index if not exists stock_movements_item_created_idx on public.stock_movements(inventory_item_id,created_at desc);

create table if not exists public.suppliers (
  id uuid primary key default gen_random_uuid(),
  supplier_code text not null unique,
  name text not null,
  contact_name text,
  phone text,
  email text,
  address text,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);
create table if not exists public.purchase_orders (
  id uuid primary key default gen_random_uuid(),
  po_number text not null unique,
  branch_id uuid not null references public.branches(id) on delete restrict,
  supplier_id uuid references public.suppliers(id) on delete set null,
  status text not null default 'draft' check (status in ('draft','submitted','approved','ordered','partially_received','received','cancelled')),
  subtotal_idr bigint not null default 0 check (subtotal_idr >= 0),
  requested_by uuid references public.admin_profiles(user_id) on delete set null,
  approved_by uuid references public.admin_profiles(user_id) on delete set null,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists purchase_orders_branch_status_idx on public.purchase_orders(branch_id,status,created_at desc);
create table if not exists public.purchase_order_items (
  id uuid primary key default gen_random_uuid(),
  purchase_order_id uuid not null references public.purchase_orders(id) on delete cascade,
  inventory_item_id uuid not null references public.inventory_items(id) on delete restrict,
  item_name_snapshot text not null,
  quantity numeric(14,3) not null check (quantity > 0),
  unit_cost_idr bigint not null check (unit_cost_idr >= 0),
  line_total_idr bigint generated always as (round(quantity * unit_cost_idr)::bigint) stored
);

create table if not exists public.pos_shifts (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches(id) on delete restrict,
  opened_by uuid not null references public.admin_profiles(user_id) on delete restrict,
  closed_by uuid references public.admin_profiles(user_id) on delete set null,
  opening_cash_idr bigint not null default 0 check (opening_cash_idr >= 0),
  expected_cash_idr bigint not null default 0 check (expected_cash_idr >= 0),
  counted_cash_idr bigint check (counted_cash_idr >= 0),
  cash_variance_idr bigint,
  status text not null default 'open' check (status in ('open','closed')),
  opened_at timestamptz not null default now(),
  closed_at timestamptz,
  notes text,
  check ((status='open' and closed_at is null) or (status='closed' and closed_at is not null))
);
create unique index if not exists pos_one_open_shift_per_cashier_branch on public.pos_shifts(branch_id,opened_by) where status='open';
create index if not exists pos_shifts_branch_opened_idx on public.pos_shifts(branch_id,opened_at desc);

create table if not exists public.pos_sales (
  id uuid primary key default gen_random_uuid(),
  transaction_code text not null unique,
  branch_id uuid not null references public.branches(id) on delete restrict,
  shift_id uuid not null references public.pos_shifts(id) on delete restrict,
  cashier_user_id uuid not null references public.admin_profiles(user_id) on delete restrict,
  subtotal_idr bigint not null check (subtotal_idr >= 0),
  discount_idr bigint not null default 0 check (discount_idr >= 0),
  total_idr bigint not null check (total_idr >= 0),
  payment_method text not null check (payment_method in ('cash','bank_transfer','qris')),
  payment_status text not null default 'paid' check (payment_status in ('paid','pending','refunded','voided')),
  customer_reference text,
  notes text,
  created_at timestamptz not null default now()
);
create index if not exists pos_sales_branch_created_idx on public.pos_sales(branch_id,created_at desc);
create index if not exists pos_sales_shift_idx on public.pos_sales(shift_id,created_at);
create table if not exists public.pos_sale_items (
  id uuid primary key default gen_random_uuid(),
  sale_id uuid not null references public.pos_sales(id) on delete cascade,
  product_id uuid references public.products(id) on delete set null,
  product_name_snapshot text not null,
  quantity integer not null check (quantity between 1 and 1000),
  unit_price_idr integer not null check (unit_price_idr >= 0),
  line_total_idr bigint not null check (line_total_idr >= 0)
);

create table if not exists public.branch_expenses (
  id uuid primary key default gen_random_uuid(),
  expense_code text not null unique,
  branch_id uuid not null references public.branches(id) on delete restrict,
  category text not null,
  description text not null,
  amount_idr bigint not null check (amount_idr > 0),
  payment_method text not null check (payment_method in ('cash','bank_transfer','qris','other')),
  status text not null default 'pending_approval' check (status in ('pending_approval','approved','rejected','paid')),
  receipt_reference text,
  created_by uuid not null references public.admin_profiles(user_id) on delete restrict,
  reviewed_by uuid references public.admin_profiles(user_id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists branch_expenses_branch_created_idx on public.branch_expenses(branch_id,created_at desc);
create index if not exists branch_expenses_status_created_idx on public.branch_expenses(status,created_at desc);

-- All ERP tables are accessed only through the authenticated Edge Function using the server-side service role.
do $$
declare t text;
begin
  foreach t in array array['branches','job_positions','branch_assignments','inventory_items','branch_inventory','stock_movements','suppliers','purchase_orders','purchase_order_items','pos_shifts','pos_sales','pos_sale_items','branch_expenses'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on table public.%I from anon, authenticated', t);
  end loop;
end $$;

create or replace function public.erp_record_stock_movement(
  p_branch_id uuid, p_inventory_item_id uuid, p_movement_type text,
  p_quantity numeric, p_notes text, p_actor_user_id uuid
) returns jsonb language plpgsql security invoker set search_path = public as $$
declare current_qty numeric(14,3); next_qty numeric(14,3); movement_id uuid;
begin
  if p_quantity is null or p_quantity <= 0 then raise exception 'invalid_quantity'; end if;
  if p_movement_type not in ('opening_balance','receipt','issue','adjustment_in','adjustment_out','transfer_in','transfer_out','waste') then raise exception 'invalid_movement_type'; end if;
  if not exists(select 1 from branches where id=p_branch_id and status='active') then raise exception 'branch_not_active'; end if;
  perform 1 from inventory_items where id=p_inventory_item_id and is_active=true;
  if not found then raise exception 'inventory_item_not_active'; end if;
  insert into branch_inventory(branch_id,inventory_item_id,on_hand)
    values(p_branch_id,p_inventory_item_id,0) on conflict(branch_id,inventory_item_id) do nothing;
  select on_hand into current_qty from branch_inventory where branch_id=p_branch_id and inventory_item_id=p_inventory_item_id for update;
  if p_movement_type in ('issue','adjustment_out','transfer_out','waste') then next_qty:=current_qty-p_quantity;
  elsif p_movement_type='opening_balance' then
    if current_qty<>0 then raise exception 'opening_balance_already_set'; end if;
    next_qty:=p_quantity;
  else next_qty:=current_qty+p_quantity; end if;
  if next_qty < 0 then raise exception 'insufficient_stock'; end if;
  update branch_inventory set on_hand=next_qty,updated_at=now() where branch_id=p_branch_id and inventory_item_id=p_inventory_item_id;
  insert into stock_movements(branch_id,inventory_item_id,movement_type,quantity,notes,created_by)
    values(p_branch_id,p_inventory_item_id,p_movement_type,p_quantity,left(coalesce(p_notes,''),500),p_actor_user_id) returning id into movement_id;
  return jsonb_build_object('ok',true,'movement_id',movement_id,'previous_quantity',current_qty,'on_hand',next_qty);
end $$;

create or replace function public.erp_create_pos_sale(
  p_branch_id uuid, p_shift_id uuid, p_items jsonb, p_payment_method text,
  p_discount_idr bigint, p_customer_reference text, p_notes text, p_actor_user_id uuid
) returns jsonb language plpgsql security invoker set search_path = public as $$
declare sh pos_shifts%rowtype; b branches%rowtype; item jsonb; p products%rowtype;
  sale_id uuid; code text; qty integer; subtotal bigint:=0; discount bigint:=greatest(coalesce(p_discount_idr,0),0);
  sale_total bigint; item_count integer:=0;
begin
  if p_payment_method not in ('cash','bank_transfer','qris') then raise exception 'invalid_payment_method'; end if;
  if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 or jsonb_array_length(p_items)>50 then raise exception 'invalid_items'; end if;
  select * into b from branches where id=p_branch_id and status='active';
  if not found then raise exception 'branch_not_active'; end if;
  select * into sh from pos_shifts where id=p_shift_id and branch_id=p_branch_id and opened_by=p_actor_user_id and status='open' for update;
  if not found then raise exception 'open_shift_required'; end if;
  for item in select * from jsonb_array_elements(p_items) loop
    qty:=nullif(item->>'quantity','')::integer;
    if qty is null or qty<1 or qty>1000 then raise exception 'invalid_quantity'; end if;
    select * into p from products where slug=item->>'slug' and is_active=true;
    if not found or p.unit_price_idr is null then raise exception 'product_unavailable'; end if;
    subtotal:=subtotal+(p.unit_price_idr::bigint*qty);
    item_count:=item_count+1;
  end loop;
  if discount>subtotal then raise exception 'discount_exceeds_subtotal'; end if;
  sale_total:=subtotal-discount;
  sale_id:=gen_random_uuid();
  code:='POS-'||b.code||'-'||to_char(now() at time zone coalesce(b.timezone,'Asia/Jakarta'),'YYYYMMDD')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,6));
  insert into pos_sales(id,transaction_code,branch_id,shift_id,cashier_user_id,subtotal_idr,discount_idr,total_idr,payment_method,payment_status,customer_reference,notes)
  values(sale_id,code,p_branch_id,p_shift_id,p_actor_user_id,subtotal,discount,sale_total,p_payment_method,'paid',left(coalesce(p_customer_reference,''),120),left(coalesce(p_notes,''),500));
  for item in select * from jsonb_array_elements(p_items) loop
    qty:=(item->>'quantity')::integer;
    select * into p from products where slug=item->>'slug' and is_active=true;
    insert into pos_sale_items(sale_id,product_id,product_name_snapshot,quantity,unit_price_idr,line_total_idr)
    values(sale_id,p.id,p.name,qty,p.unit_price_idr,p.unit_price_idr::bigint*qty);
  end loop;
  if p_payment_method='cash' then update pos_shifts set expected_cash_idr=expected_cash_idr+sale_total where id=p_shift_id; end if;
  insert into admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
  values(p_actor_user_id,'pos_sale_created','pos_sale',sale_id::text,jsonb_build_object('branch_id',p_branch_id,'transaction_code',code,'total_idr',sale_total,'payment_method',p_payment_method));
  return jsonb_build_object('ok',true,'sale_id',sale_id,'transaction_code',code,'subtotal_idr',subtotal,'discount_idr',discount,'total_idr',sale_total,'items_count',item_count);
end $$;

revoke all on function public.erp_record_stock_movement(uuid,uuid,text,numeric,text,uuid) from public, anon, authenticated;
grant execute on function public.erp_record_stock_movement(uuid,uuid,text,numeric,text,uuid) to service_role;
revoke all on function public.erp_create_pos_sale(uuid,uuid,jsonb,text,bigint,text,text,uuid) from public, anon, authenticated;
grant execute on function public.erp_create_pos_sale(uuid,uuid,jsonb,text,bigint,text,text,uuid) to service_role;
