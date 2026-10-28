-- Disposable PostgreSQL regression test for the stock-transfer tenant boundary.
-- Runs only in an ephemeral CI database; it never connects to shared Supabase.
\set ON_ERROR_STOP on

-- Supabase roles referenced by the migration; these are test-only roles.
create role anon nologin;
create role authenticated nologin;

create table public.branches (
  id uuid primary key,
  tenant_id uuid not null,
  is_active boolean not null default true
);

create table public.stock_transfers (
  id uuid primary key default gen_random_uuid(),
  source_branch_id uuid not null,
  destination_branch_id uuid not null
);

insert into public.branches (id, tenant_id) values
  ('10000000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  ('10000000-0000-0000-0000-000000000002', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  ('20000000-0000-0000-0000-000000000001', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');

\ir ../../supabase/migrations/20261028120000_enforce_same_tenant_stock_transfers.sql

-- Same-tenant transfer is allowed.
insert into public.stock_transfers (source_branch_id, destination_branch_id)
values ('10000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000002');

do $test$
declare
  v_error text;
  v_count integer;
begin
  -- Cross-tenant INSERT must fail with the exact guard error.
  v_error := null;
  begin
    insert into public.stock_transfers (source_branch_id, destination_branch_id)
    values ('10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001');
  exception when others then
    v_error := sqlerrm;
  end;
  if v_error is distinct from 'stock_transfer_cross_tenant_forbidden' then
    raise exception 'expected cross-tenant insert rejection, got: %', coalesce(v_error, 'NO ERROR');
  end if;

  -- Cross-tenant UPDATE must fail too.
  v_error := null;
  begin
    update public.stock_transfers
       set destination_branch_id = '20000000-0000-0000-0000-000000000001'
     where source_branch_id = '10000000-0000-0000-0000-000000000001';
  exception when others then
    v_error := sqlerrm;
  end;
  if v_error is distinct from 'stock_transfer_cross_tenant_forbidden' then
    raise exception 'expected cross-tenant update rejection, got: %', coalesce(v_error, 'NO ERROR');
  end if;

  select count(*) into v_count from public.stock_transfers;
  if v_count <> 1 then
    raise exception 'denied writes changed stock_transfers unexpectedly; expected 1 row, got %', v_count;
  end if;

  -- Missing source branch must fail closed.
  v_error := null;
  begin
    insert into public.stock_transfers (source_branch_id, destination_branch_id)
    values ('30000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000002');
  exception when others then
    v_error := sqlerrm;
  end;
  if v_error is distinct from 'stock_transfer_source_branch_missing' then
    raise exception 'expected missing-source rejection, got: %', coalesce(v_error, 'NO ERROR');
  end if;
end;
$test$;

select 'stock-transfer-tenant-boundary-regression: PASS' as result;
