-- Enforce tenant/branch consistency at the database boundary.
-- This complements, but does not replace, tenant-aware authorization in every Edge Function action.

do $$ begin
  if not exists(select 1 from pg_constraint where conname='branches_tenant_id_id_key' and conrelid='public.branches'::regclass) then
    alter table public.branches add constraint branches_tenant_id_id_key unique(tenant_id,id);
  end if;
  if not exists(select 1 from pg_constraint where conname='warehouses_branch_id_id_key' and conrelid='public.warehouses'::regclass) then
    alter table public.warehouses add constraint warehouses_branch_id_id_key unique(branch_id,id);
  end if;
end $$;

do $$ begin
  if not exists(select 1 from pg_constraint where conname='warehouses_tenant_branch_fkey' and conrelid='public.warehouses'::regclass) then
    alter table public.warehouses add constraint warehouses_tenant_branch_fkey
      foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict;
  end if;
  if not exists(select 1 from pg_constraint where conname='branch_settings_tenant_branch_fkey' and conrelid='public.branch_settings'::regclass) then
    alter table public.branch_settings add constraint branch_settings_tenant_branch_fkey
      foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict;
  end if;
  if not exists(select 1 from pg_constraint where conname='shift_handover_tenant_branch_fkey' and conrelid='public.shift_handover_records'::regclass) then
    alter table public.shift_handover_records add constraint shift_handover_tenant_branch_fkey
      foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict;
  end if;
  if not exists(select 1 from pg_constraint where conname='inventory_waste_tenant_branch_fkey' and conrelid='public.inventory_waste_events'::regclass) then
    alter table public.inventory_waste_events add constraint inventory_waste_tenant_branch_fkey
      foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict;
  end if;
  if not exists(select 1 from pg_constraint where conname='integration_outbox_tenant_branch_fkey' and conrelid='public.integration_outbox'::regclass) then
    alter table public.integration_outbox add constraint integration_outbox_tenant_branch_fkey
      foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict;
  end if;
  if not exists(select 1 from pg_constraint where conname='branch_inventory_branch_warehouse_fkey' and conrelid='public.branch_inventory'::regclass) then
    alter table public.branch_inventory add constraint branch_inventory_branch_warehouse_fkey
      foreign key(branch_id,warehouse_id) references public.warehouses(branch_id,id) on delete restrict;
  end if;
end $$;
