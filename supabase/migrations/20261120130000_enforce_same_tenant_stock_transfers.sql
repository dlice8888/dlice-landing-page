-- Enforce stock transfers as an intra-tenant workflow at the database boundary.
-- Cross-tenant logistics requires a separate, explicitly designed workflow.
-- This forward-only migration supersedes the stale 20261028120000 proposal from PR #64.

create or replace function public.enforce_stock_transfer_same_tenant()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $function$
declare
  v_source_tenant uuid;
  v_destination_tenant uuid;
begin
  select b.tenant_id
    into v_source_tenant
    from public.branches b
   where b.id = new.source_branch_id;

  if v_source_tenant is null then
    raise exception 'stock_transfer_source_branch_missing';
  end if;

  select b.tenant_id
    into v_destination_tenant
    from public.branches b
   where b.id = new.destination_branch_id;

  if v_destination_tenant is null then
    raise exception 'stock_transfer_destination_branch_missing';
  end if;

  if v_source_tenant is distinct from v_destination_tenant then
    raise exception 'stock_transfer_cross_tenant_forbidden';
  end if;

  return new;
end;
$function$;

drop trigger if exists trg_stock_transfer_same_tenant on public.stock_transfers;

create trigger trg_stock_transfer_same_tenant
before insert or update of source_branch_id, destination_branch_id
on public.stock_transfers
for each row
execute function public.enforce_stock_transfer_same_tenant();

revoke all on function public.enforce_stock_transfer_same_tenant() from public, anon, authenticated;

-- A branch tenant reassignment must not invalidate historical stock-transfer scope.
-- This permits reassignment only while the branch has no stock-transfer history.
create or replace function public.prevent_branch_tenant_reassignment_with_stock_transfers()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $function$
begin
  if new.tenant_id is distinct from old.tenant_id
     and exists (
       select 1
         from public.stock_transfers st
        where st.source_branch_id = old.id
           or st.destination_branch_id = old.id
     ) then
    raise exception 'branch_tenant_change_with_stock_transfers_forbidden';
  end if;

  return new;
end;
$function$;

drop trigger if exists trg_branch_tenant_reassignment_with_stock_transfers on public.branches;

create trigger trg_branch_tenant_reassignment_with_stock_transfers
before update of tenant_id
on public.branches
for each row
execute function public.prevent_branch_tenant_reassignment_with_stock_transfers();

revoke all on function public.prevent_branch_tenant_reassignment_with_stock_transfers() from public, anon, authenticated;
