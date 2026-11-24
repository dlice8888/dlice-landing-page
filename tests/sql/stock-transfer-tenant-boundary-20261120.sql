-- Disposable PostgreSQL regression for the stock-transfer tenant boundary.
-- This test never connects to shared staging or production.
\set ON_ERROR_STOP on

create role anon nologin;
create role authenticated nologin;

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
  ('90000000-0000-4000-8000-000000000004', '00000000-0000-4000-8000-000000000002'),
  ('90000000-0000-4000-8000-000000000005', '00000000-0000-4000-8000-000000000001'),
  ('90000000-0000-4000-8000-000000000006', '00000000-0000-4000-8000-000000000001');

\i supabase/migrations/20261120130000_enforce_same_tenant_stock_transfers.sql


-- The trigger must lock both branch rows before reading tenant IDs so a
-- concurrent branch tenant reassignment cannot pass the same check.
do $test$
begin
  if position(
    'FOR SHARE' in upper(pg_get_functiondef(
      'public.enforce_stock_transfer_same_tenant()'::regprocedure
    ))
  ) = 0 then
    raise exception 'TEST_FAILURE: tenant guard does not lock branch rows';
  end if;
end
$test$;

-- A same-tenant transfer is valid.
insert into public.stock_transfers (id, source_branch_id, destination_branch_id)
values ('a0000000-0000-4000-8000-000000000001',
        '90000000-0000-4000-8000-000000000001',
        '90000000-0000-4000-8000-000000000002');

-- A cross-tenant insert must fail with the guard's exact reason.
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
      if sqlerrm = 'TEST_FAILURE: cross-tenant insert was accepted' then raise; end if;
      if sqlerrm <> 'stock_transfer_cross_tenant_forbidden' then
        raise exception 'TEST_FAILURE: unexpected insert rejection: %', sqlerrm;
      end if;
  end;
end
$test$;

-- Updating the destination to another tenant must fail.
do $test$
begin
  begin
    update public.stock_transfers
       set destination_branch_id = '90000000-0000-4000-8000-000000000004'
     where id = 'a0000000-0000-4000-8000-000000000001';
    raise exception 'TEST_FAILURE: cross-tenant destination update was accepted';
  exception
    when raise_exception then
      if sqlerrm = 'TEST_FAILURE: cross-tenant destination update was accepted' then raise; end if;
      if sqlerrm <> 'stock_transfer_cross_tenant_forbidden' then
        raise exception 'TEST_FAILURE: unexpected destination update rejection: %', sqlerrm;
      end if;
  end;
end
$test$;

-- Reassigning a branch's tenant must not invalidate a transfer already referencing it.
do $test$
begin
  begin
    update public.branches
       set tenant_id = '00000000-0000-4000-8000-000000000002'
     where id = '90000000-0000-4000-8000-000000000002';
    raise exception 'TEST_FAILURE: branch tenant reassignment with transfer history was accepted';
  exception
    when raise_exception then
      if sqlerrm = 'TEST_FAILURE: branch tenant reassignment with transfer history was accepted' then raise; end if;
      if sqlerrm <> 'branch_tenant_change_with_stock_transfers_forbidden' then
        raise exception 'TEST_FAILURE: unexpected branch reassignment rejection: %', sqlerrm;
      end if;
  end;
end
$test$;

-- Updating the source to another tenant must fail.
do $test$
begin
  begin
    update public.stock_transfers
       set source_branch_id = '90000000-0000-4000-8000-000000000004'
     where id = 'a0000000-0000-4000-8000-000000000001';
    raise exception 'TEST_FAILURE: cross-tenant source update was accepted';
  exception
    when raise_exception then
      if sqlerrm = 'TEST_FAILURE: cross-tenant source update was accepted' then raise; end if;
      if sqlerrm <> 'stock_transfer_cross_tenant_forbidden' then
        raise exception 'TEST_FAILURE: unexpected source update rejection: %', sqlerrm;
      end if;
  end;
end
$test$;

-- Confirm failed writes did not leave extra rows or mutate the valid transfer.
do $test$
declare
  row_count integer;
  source uuid;
  destination uuid;
begin
  select count(*) into row_count from public.stock_transfers;
  if row_count <> 1 then
    raise exception 'TEST_FAILURE: expected one committed same-tenant transfer, got %', row_count;
  end if;
  select source_branch_id, destination_branch_id into source, destination
    from public.stock_transfers
   where id = 'a0000000-0000-4000-8000-000000000001';
  if source <> '90000000-0000-4000-8000-000000000001'
     or destination <> '90000000-0000-4000-8000-000000000002' then
    raise exception 'TEST_FAILURE: rejected update mutated the valid transfer';
  end if;
  if has_function_privilege('anon', 'public.enforce_stock_transfer_same_tenant()', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.enforce_stock_transfer_same_tenant()', 'EXECUTE') then
    raise exception 'TEST_FAILURE: client role can execute trigger function directly';
  end if;
end
$test$;

\echo 'PASS: same-tenant insert succeeds; cross-tenant insert and both branch updates fail; no partial writes; client EXECUTE denied.'
