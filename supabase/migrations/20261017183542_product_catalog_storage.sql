-- Product catalog metadata and public product-photo storage.
-- Existing products/orders are preserved; no order tables are modified.
alter table public.products
  add column if not exists image_path text,
  add column if not exists category text not null default 'pastry',
  add column if not exists display_order integer not null default 100,
  add column if not exists badge text;

update public.products
set category = case
  when slug = 'es-buah-premium' then 'fresh'
  else 'pastry'
end,
display_order = case
  when slug = 'es-buah-premium' then 10
  when slug = 'cadbury-braid-cheese' then 20
  when slug = 'cadbury-kunafa-pistachio-braid' then 30
  else display_order
end,
badge = case
  when slug = 'es-buah-premium' then 'FRESH FAVORITE'
  when slug = 'cadbury-braid-cheese' then 'CROWD PLEASER'
  when slug = 'cadbury-kunafa-pistachio-braid' then 'MUST TRY'
  else badge
end;

alter table public.products
  drop constraint if exists products_category_check;
alter table public.products
  add constraint products_category_check check (category in ('fresh','pastry','other'));
alter table public.products
  drop constraint if exists products_display_order_check;
alter table public.products
  add constraint products_display_order_check check (display_order >= 0);

alter table public.products enable row level security;
drop policy if exists "Public can read active Dlice products" on public.products;
create policy "Public can read active Dlice products"
  on public.products for select to anon, authenticated
  using (is_active = true);

grant select on public.products to anon, authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('dlice-product-photos', 'dlice-product-photos', true, 5242880, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update
set public = true, file_size_limit = 5242880, allowed_mime_types = array['image/jpeg','image/png','image/webp'];

comment on column public.products.image_path is 'Object path in the dlice-product-photos Storage bucket.';
comment on column public.products.category is 'Public menu category: fresh, pastry, or other.';
comment on column public.products.display_order is 'Ascending order in which the product is displayed.';
