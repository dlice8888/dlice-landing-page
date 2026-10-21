-- D'Lice FnB OS synthetic fixtures. STAGING ONLY.
-- Safe defaults: active ERP branches, but online checkout is explicitly disabled.
-- Product is inactive so it cannot appear in the public staging storefront.
-- Run only against Supabase project higoadrzxnhzbbwhdbmh.
begin;

insert into public.branches
  (id, code, name, status, timezone, accepts_online_orders, pickup_enabled, delivery_enabled, daily_order_capacity, notes)
values
  ('90000000-0000-4000-8000-000000000001', 'QA-DLICE-A', '[TEST] Dlice QA Branch A - WIB', 'active', 'Asia/Jakarta', false, true, false, 100, 'SYNTHETIC TEST FIXTURE ONLY; online checkout disabled'),
  ('90000000-0000-4000-8000-000000000002', 'QA-DLICE-B', '[TEST] Dlice QA Branch B - WITA', 'active', 'Asia/Makassar', false, true, false, 100, 'SYNTHETIC TEST FIXTURE ONLY; online checkout disabled'),
  ('90000000-0000-4000-8000-000000000003', 'QA-DLICE-C', '[TEST] Dlice QA Branch C - WIT', 'active', 'Asia/Jayapura', false, true, false, 100, 'SYNTHETIC TEST FIXTURE ONLY; online checkout disabled')
on conflict (id) do update set
  code = excluded.code,
  name = excluded.name,
  status = excluded.status,
  timezone = excluded.timezone,
  accepts_online_orders = false,
  pickup_enabled = true,
  delivery_enabled = false,
  daily_order_capacity = excluded.daily_order_capacity,
  notes = excluded.notes;

insert into public.products
  (id, slug, name, description, unit_price_idr, is_active, category, display_order, badge)
values
  ('90000000-0000-4000-8000-000000000100', 'qa-staging-only-fixture', '[TEST ONLY] Staging QA Fixture Product', 'Synthetic inactive product for staging acceptance tests; never a sellable menu item.', 100, false, 'other', 99999, 'STAGING TEST ONLY')
on conflict (id) do update set
  slug = excluded.slug,
  name = excluded.name,
  description = excluded.description,
  unit_price_idr = excluded.unit_price_idr,
  is_active = false,
  category = excluded.category,
  display_order = excluded.display_order,
  badge = excluded.badge;

insert into public.inventory_items
  (id, sku, name, unit, category, min_stock, is_active)
values
  ('90000000-0000-4000-8000-000000000201', 'QA-DLICE-FLOUR', '[TEST] Flour for staging workflow', 'g', 'ingredients', 0, true),
  ('90000000-0000-4000-8000-000000000202', 'QA-DLICE-SUGAR', '[TEST] Sugar for staging workflow', 'g', 'ingredients', 0, true)
on conflict (id) do update set
  sku = excluded.sku,
  name = excluded.name,
  unit = excluded.unit,
  category = excluded.category,
  min_stock = 0,
  is_active = true;

insert into public.suppliers
  (id, supplier_code, name, contact_name, phone, email, address, is_active)
values
  ('90000000-0000-4000-8000-000000000301', 'QA-DLICE-SUPPLIER', '[TEST] Staging supplier only', 'Synthetic QA', null, 'qa-fixture@example.invalid', 'Non-deliverable synthetic address', true)
on conflict (id) do update set
  supplier_code = excluded.supplier_code,
  name = excluded.name,
  contact_name = excluded.contact_name,
  phone = null,
  email = excluded.email,
  address = excluded.address,
  is_active = true;

insert into public.recipes
  (id, product_id, version, yield_quantity, yield_unit, status, effective_from, instructions)
values
  ('90000000-0000-4000-8000-000000000401', '90000000-0000-4000-8000-000000000100', 1, 10, 'pcs', 'draft', current_date, 'SYNTHETIC STAGING RECIPE ONLY; requires approval before activation')
on conflict (id) do update set
  product_id = excluded.product_id,
  version = excluded.version,
  yield_quantity = excluded.yield_quantity,
  yield_unit = excluded.yield_unit,
  status = 'draft',
  effective_from = excluded.effective_from,
  instructions = excluded.instructions;

insert into public.recipe_ingredients
  (id, recipe_id, inventory_item_id, quantity_per_yield, unit, is_optional)
values
  ('90000000-0000-4000-8000-000000000501', '90000000-0000-4000-8000-000000000401', '90000000-0000-4000-8000-000000000201', 500, 'g', false),
  ('90000000-0000-4000-8000-000000000502', '90000000-0000-4000-8000-000000000401', '90000000-0000-4000-8000-000000000202', 100, 'g', false)
on conflict (id) do update set
  recipe_id = excluded.recipe_id,
  inventory_item_id = excluded.inventory_item_id,
  quantity_per_yield = excluded.quantity_per_yield,
  unit = excluded.unit,
  is_optional = excluded.is_optional;

commit;

-- Verify: all three branches must still have accepts_online_orders=false,
-- the product must be inactive, and the recipe must remain draft.
select code, status, timezone, accepts_online_orders
from public.branches where code like 'QA-DLICE-%' order by code;
select id, slug, is_active from public.products where id = '90000000-0000-4000-8000-000000000100';
select id, status, product_id from public.recipes where id = '90000000-0000-4000-8000-000000000401';
