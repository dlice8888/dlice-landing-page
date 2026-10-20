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
