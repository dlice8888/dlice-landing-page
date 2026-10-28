-- Free, isolated PostgreSQL regression test for the stock-transfer tenant trigger.
-- This intentionally creates only the minimum schema needed by the migration.
-- It is not a substitute for replaying the migration against the full staging schema.
\set ON_ERROR_STOP on

create table public.branches (
  id uuid primary key,
  tenant_id uuid not null
);

create table public.stock_transfers (
  id uuid primary key,
  source_branch_id uuid not null references public.branches(id),
  destination_branch_id uuid not null references public.branches(id)
);

insert into public.branches (id, tenant_id) values
  ('90000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000001'),
  ('90000000-0000-4000-8000-000000000002', '00000000-0000-4000-8000-000000000001'),
  ('90000000-0000-4000-8000-000000000004', '00000000-0000-4000-8000-000000000002');

\echo 'Applying exact migration under test'
\i supabase/migrations/20261028120000_enforce_same_tenant_stock_transfers.sql

\echo 'Same-tenant transfer insert must succeed'
insert into public.stock_transfers (id, source_branch_id, destination_branch_id)
values ('a0000000-0000-4000-8000-000000000001',
        '90000000-0000-4000-8000-000000000001',
        '90000000-0000-4000-8000-000000000002');

\echo 'Cross-tenant insert must fail with the expected guard'
do $test$
begin
  begin
    insert into public.stock_transfers (id, source_branch_id, destination_branch_id)
    values ('a0000000-0000-4000-8000-000000000002',
            '90000000-0000-4000-8000-000000000001',
            '90000000-0000-4000-8000-000000000004');
    raise exception 'TEST_FAILURE: cross-tenant insert was accepted';
  exception
    when raise_exception then
      if sqlerrm = 'TEST_FAILURE: cross-tenant insert was accepted' then
        raise;
      end if;
      if sqlerrm <> 'stock_transfer_cross_tenant_forbidden' then
        raise exception 'TEST_FAILURE: unexpected insert rejection: %', sqlerrm;
      end if;
  end;
end
$test$;

\echo 'Cross-tenant update must fail and preserve original row'
do $test$
begin
  begin
    update public.stock_transfers
       set destination_branch_id = '90000000-0000-4000-8000-000000000004'
     where id = 'a0000000-0000-4000-8000-000000000001';
    raise exception 'TEST_FAILURE: cross-tenant update was accepted';
  exception
    when raise_exception then
      if sqlerrm = 'TEST_FAILURE: cross-tenant update was accepted' then
        raise;
      end if;
      if sqlerrm <> 'stock_transfer_cross_tenant_forbidden' then
        raise exception 'TEST_FAILURE: unexpected update rejection: %', sqlerrm;
      end if;
  end;
end
$test$;

do $test$
declare
  row_count integer;
  destination uuid;
begin
  select count(*) into row_count from public.stock_transfers;
  if row_count <> 1 then
    raise exception 'TEST_FAILURE: expected exactly one committed same-tenant transfer, got %', row_count;
  end if;
  select destination_branch_id into destination
    from public.stock_transfers
   where id = 'a0000000-0000-4000-8000-000000000001';
  if destination <> '90000000-0000-4000-8000-000000000002' then
    raise exception 'TEST_FAILURE: rejected update changed the destination branch';
  end if;
end
$test$;

\echo 'PASS: same-tenant insert succeeds; cross-tenant insert/update fail; rejected update preserves data.'
