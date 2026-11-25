-- DESIGN DRAFT ONLY — companion to HR_PAYROLL_FINANCE_SCHEMA_DRAFT.sql.
-- No payment provider is enabled and no payroll payment has been executed.

create table if not exists public.hr_payroll_provider_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  payment_batch_id uuid not null,
  provider_id text not null,
  provider_event_id text not null,
  provider_reference text null,
  payment_item_id uuid null,
  event_status text not null check(event_status in ('accepted','settled','failed','reversed')),
  amount_idr bigint not null check(amount_idr>0),
  payload_sha256 text not null check(payload_sha256 ~ '^[0-9a-f]{64}$'),
  occurred_at timestamptz not null,
  received_at timestamptz not null default now(),
  unique(tenant_id,id),
  unique(provider_id,provider_event_id),
  foreign key(tenant_id,payment_batch_id) references public.hr_payroll_payment_batches(tenant_id,id) on delete restrict,
  foreign key(tenant_id,payment_item_id) references public.hr_payroll_payment_items(tenant_id,id) on delete restrict
);

create table if not exists public.hr_payroll_payment_reconciliations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  payment_batch_id uuid not null,
  expected_amount_idr bigint not null check(expected_amount_idr>0),
  settled_amount_idr bigint not null check(settled_amount_idr>=0),
  provider_reference text not null,
  evidence_sha256 text not null check(evidence_sha256 ~ '^[0-9a-f]{64}$'),
  status text not null check(status in ('reconciled','exception')),
  reconciled_by uuid null references auth.users(id) on delete restrict,
  reconciled_at timestamptz null,
  unique(tenant_id,id),
  unique(tenant_id,payment_batch_id),
  foreign key(tenant_id,payment_batch_id) references public.hr_payroll_payment_batches(tenant_id,id) on delete restrict,
  check((status='reconciled' and expected_amount_idr=settled_amount_idr and reconciled_by is not null and reconciled_at is not null) or status<>'reconciled')
);

create or replace function public.hr_create_payroll_payment_intent(
  p_tenant_id uuid,p_branch_id uuid,p_payroll_run_id uuid,p_finance_batch_id uuid,
  p_provider_id text,p_idempotency_key text,p_actor_user_id uuid,p_items jsonb
) returns jsonb
language plpgsql security invoker set search_path=''
as $$
declare
  v_run public.hr_payroll_runs%rowtype;
  v_finance public.finance_journal_batches%rowtype;
  v_prior public.hr_payroll_payment_batches%rowtype;
  v_batch public.hr_payroll_payment_batches%rowtype;
  v_total bigint;
  v_count integer;
begin
  if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0
     or length(coalesce(p_idempotency_key,'')) not between 8 and 160 then
    raise exception using errcode='22023',message='INVALID_PAYROLL_PAYMENT_INTENT';
  end if;
  select * into v_run from public.hr_payroll_runs
   where tenant_id=p_tenant_id and branch_id=p_branch_id and id=p_payroll_run_id
   for update;
  if not found or v_run.status<>'posted' then
    raise exception using errcode='23514',message='PAYROLL_RUN_NOT_POSTED';
  end if;
  select * into v_finance from public.finance_journal_batches
   where tenant_id=p_tenant_id and id=p_finance_batch_id and source_type='hr_payroll_run'
     and source_id=p_payroll_run_id for update;
  if not found or v_finance.status<>'posted' then
    raise exception using errcode='23514',message='PAYROLL_FINANCE_BATCH_NOT_POSTED';
  end if;
  if not exists(select 1 from public.finance_source_reconciliations
    where tenant_id=p_tenant_id and source_type='hr_payroll_run'
      and source_id=p_payroll_run_id and journal_batch_id=p_finance_batch_id and status='reconciled') then
    raise exception using errcode='23514',message='PAYROLL_FINANCE_SOURCE_NOT_RECONCILED';
  end if;
  select count(*),coalesce(sum(x.amount_idr),0)
    into v_count,v_total
    from jsonb_to_recordset(p_items) as x(payroll_line_id uuid,beneficiary_reference_hash text,amount_idr bigint);
  if v_count<>v_run.employee_count or v_total<>v_run.net_amount_idr
     or exists(
       select 1 from jsonb_to_recordset(p_items) as x(payroll_line_id uuid,beneficiary_reference_hash text,amount_idr bigint)
       left join public.hr_payroll_run_lines l on l.tenant_id=p_tenant_id
         and l.payroll_run_id=p_payroll_run_id and l.id=x.payroll_line_id
       where l.id is null or x.amount_idr<>l.net_amount_idr
         or x.beneficiary_reference_hash !~ '^[0-9a-f]{64}$'
     ) then
    raise exception using errcode='23514',message='PAYROLL_PAYMENT_ITEMS_DO_NOT_RECONCILE';
  end if;
  select * into v_prior from public.hr_payroll_payment_batches
   where tenant_id=p_tenant_id and idempotency_key=p_idempotency_key for update;
  if found then
    if v_prior.payroll_run_id<>p_payroll_run_id or v_prior.amount_idr<>v_total
       or v_prior.finance_batch_id<>p_finance_batch_id then
      raise exception using errcode='23505',message='PAYROLL_PAYMENT_IDEMPOTENCY_COLLISION';
    end if;
    return jsonb_build_object('status','duplicate','payment_batch_id',v_prior.id,'amount_idr',v_prior.amount_idr);
  end if;
  insert into public.hr_payroll_payment_batches(
    tenant_id,branch_id,payroll_run_id,finance_batch_id,provider_id,status,amount_idr,idempotency_key,created_by
  ) values(p_tenant_id,p_branch_id,p_payroll_run_id,p_finance_batch_id,p_provider_id,
    'intent_created',v_total,p_idempotency_key,p_actor_user_id)
  returning * into v_batch;
  insert into public.hr_payroll_payment_items(
    tenant_id,payment_batch_id,payroll_line_id,beneficiary_reference_hash,amount_idr
  )
  select p_tenant_id,v_batch.id,x.payroll_line_id,x.beneficiary_reference_hash,x.amount_idr
  from jsonb_to_recordset(p_items) as x(payroll_line_id uuid,beneficiary_reference_hash text,amount_idr bigint);
  insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
  values(p_actor_user_id,'hr.payroll.payment_intent_created','hr_payroll_payment_batches',v_batch.id::text,
    jsonb_build_object('tenant_id',p_tenant_id,'payroll_run_id',p_payroll_run_id,'amount_idr',v_total));
  return jsonb_build_object('status','intent_created','payment_batch_id',v_batch.id,'amount_idr',v_total);
end;
$$;
revoke all on function public.hr_create_payroll_payment_intent(uuid,uuid,uuid,uuid,text,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.hr_create_payroll_payment_intent(uuid,uuid,uuid,uuid,text,text,uuid,jsonb) to service_role;

do $$
declare t text;
begin
  foreach t in array array['hr_payroll_provider_events','hr_payroll_payment_reconciliations'] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('drop policy if exists service_role_only on public.%I',t);
    execute format('create policy service_role_only on public.%I for all to service_role using (true) with check (true)',t);
    execute format('revoke all on public.%I from anon, authenticated',t);
    execute format('grant select,insert,update,delete on public.%I to service_role',t);
  end loop;
end $$;
