-- Cleanup for tests/staging/fixtures.sql. STAGING ONLY.
-- Run only after all acceptance evidence is captured.
-- Refuses to delete fixtures if business transactions still reference them.

begin;
do $$
begin
  if exists (select 1 from public.orders where branch_id in (
      '90000000-0000-4000-8000-000000000001'::uuid,
      '90000000-0000-4000-8000-000000000002'::uuid,
      '90000000-0000-4000-8000-000000000003'::uuid
    )) then raise exception 'Cleanup blocked: orders still reference QA branches'; end if;
  if exists (select 1 from public.pos_shifts where branch_id in (
      '90000000-0000-4000-8000-000000000001'::uuid,
      '90000000-0000-4000-8000-000000000002'::uuid,
      '90000000-0000-4000-8000-000000000003'::uuid
    )) then raise exception 'Cleanup blocked: POS shifts still reference QA branches'; end if;
  if exists (select 1 from public.purchase_orders where branch_id in (
      '90000000-0000-4000-8000-000000000001'::uuid,
      '90000000-0000-4000-8000-000000000002'::uuid,
      '90000000-0000-4000-8000-000000000003'::uuid
    )) then raise exception 'Cleanup blocked: purchase orders still reference QA branches'; end if;
  if exists (select 1 from public.production_batches where branch_id in (
      '90000000-0000-4000-8000-000000000001'::uuid,
      '90000000-0000-4000-8000-000000000002'::uuid,
      '90000000-0000-4000-8000-000000000003'::uuid
    )) then raise exception 'Cleanup blocked: production batches still reference QA branches'; end if;
  if exists (select 1 from public.branch_assignments where branch_id in (
      '90000000-0000-4000-8000-000000000001'::uuid,
      '90000000-0000-4000-8000-000000000002'::uuid,
      '90000000-0000-4000-8000-000000000003'::uuid
    )) then raise exception 'Cleanup blocked: branch assignments still reference QA branches'; end if;
  if exists (select 1 from public.branch_product_capacity where branch_id in (
      '90000000-0000-4000-8000-000000000001'::uuid,
      '90000000-0000-4000-8000-000000000002'::uuid,
      '90000000-0000-4000-8000-000000000003'::uuid
    ) and id <> '90000000-0000-4000-8000-000000000601'::uuid)
    then raise exception 'Cleanup blocked: other capacity rows reference QA branches'; end if;
  if exists (select 1 from public.order_items where product_id = '90000000-0000-4000-8000-000000000100'::uuid)
    then raise exception 'Cleanup blocked: order items still reference QA product'; end if;
  if exists (select 1 from public.pos_sale_items where product_id = '90000000-0000-4000-8000-000000000100'::uuid)
    then raise exception 'Cleanup blocked: POS items still reference QA product'; end if;
  if exists (select 1 from public.branch_product_capacity where product_id = '90000000-0000-4000-8000-000000000100'::uuid and id <> '90000000-0000-4000-8000-000000000601'::uuid)
    then raise exception 'Cleanup blocked: additional branch capacity rows still reference QA product'; end if;
end $$;

delete from public.branch_product_capacity
where id = '90000000-0000-4000-8000-000000000601'::uuid;
delete from public.recipe_ingredients
where recipe_id = '90000000-0000-4000-8000-000000000401'::uuid;
delete from public.recipes
where id = '90000000-0000-4000-8000-000000000401'::uuid;
delete from public.products
where id = '90000000-0000-4000-8000-000000000100'::uuid;
delete from public.inventory_items
where id in ('90000000-0000-4000-8000-000000000201'::uuid, '90000000-0000-4000-8000-000000000202'::uuid);
delete from public.suppliers
where id = '90000000-0000-4000-8000-000000000301'::uuid;
delete from public.branches
where id in (
  '90000000-0000-4000-8000-000000000001'::uuid,
  '90000000-0000-4000-8000-000000000002'::uuid,
  '90000000-0000-4000-8000-000000000003'::uuid
);
commit;
