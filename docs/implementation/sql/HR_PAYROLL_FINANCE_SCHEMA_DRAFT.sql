-- DESIGN DRAFT ONLY — NOT A MIGRATION.
-- No payroll tables were present in the inspected staging public schema.
-- This draft provides a tenant-scoped, immutable payroll and Finance contract.
-- It must be reconciled with the existing finance_journal_entries model before migration.

create table if not exists public.hr_employees (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  branch_id uuid not null,
  employee_code text not null check(employee_code ~ '^[A-Z0-9_-]{2,40}$'),
  display_name text not null check(length(btrim(display_name)) between 1 and 160),
  employment_type text not null check(employment_type in ('monthly','hourly','contract')),
  status text not null default 'active' check(status in ('active','leave','suspended','terminated')),
  hired_on date not null,
  terminated_on date null,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tenant_id,id),
  unique(tenant_id,employee_code),
  foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict,
  check(terminated_on is null or terminated_on>=hired_on)
);

create table if not exists public.hr_payroll_profiles (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  employee_id uuid not null,
  effective_from date not null,
  effective_to date null,
  monthly_base_idr bigint not null default 0 check(monthly_base_idr>=0),
  hourly_rate_idr bigint not null default 0 check(hourly_rate_idr>=0),
  overtime_multiplier numeric(6,3) not null default 1.500 check(overtime_multiplier between 1 and 5),
  allowance_rules jsonb not null default '{}'::jsonb check(jsonb_typeof(allowance_rules)='object'),
  benefit_rules jsonb not null default '{}'::jsonb check(jsonb_typeof(benefit_rules)='object'),
  tax_profile jsonb not null default '{}'::jsonb check(jsonb_typeof(tax_profile)='object'),
  deduction_rules jsonb not null default '{}'::jsonb check(jsonb_typeof(deduction_rules)='object'),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique(tenant_id,id),
  foreign key(tenant_id,employee_id) references public.hr_employees(tenant_id,id) on delete restrict,
  check(effective_to is null or effective_to>=effective_from),
  check((monthly_base_idr>0 and hourly_rate_idr=0) or (hourly_rate_idr>0 and monthly_base_idr=0) or (monthly_base_idr=0 and hourly_rate_idr=0))
);
create index if not exists hr_payroll_profile_effective_idx
  on public.hr_payroll_profiles(tenant_id,employee_id,effective_from desc);

create table if not exists public.hr_payroll_runs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  branch_id uuid not null,
  period_start date not null,
  period_end date not null,
  status text not null default 'draft' check(status in ('draft','calculated','submitted','approved','posted','payment_pending','paid','reconciled','void')),
  currency text not null default 'IDR' check(currency='IDR'),
  employee_count integer not null default 0 check(employee_count>=0),
  gross_amount_idr bigint not null default 0 check(gross_amount_idr>=0),
  deductions_amount_idr bigint not null default 0 check(deductions_amount_idr>=0),
  employer_contributions_idr bigint not null default 0 check(employer_contributions_idr>=0),
  net_amount_idr bigint not null default 0 check(net_amount_idr>=0),
  idempotency_key text not null check(length(idempotency_key) between 8 and 160),
  calculation_version text not null,
  submitted_by uuid null references auth.users(id) on delete restrict,
  submitted_at timestamptz null,
  approved_by uuid null references auth.users(id) on delete restrict,
  approved_at timestamptz null,
  posted_at timestamptz null,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tenant_id,id),
  unique(tenant_id,branch_id,period_start,period_end),
  unique(tenant_id,idempotency_key),
  foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict,
  check(period_end>=period_start),
  check(gross_amount_idr-deductions_amount_idr=net_amount_idr),
  check((status in ('approved','posted','payment_pending','paid','reconciled') and approved_by is not null and approved_at is not null and approved_by<>created_by) or status not in ('approved','posted','payment_pending','paid','reconciled'))
);

create table if not exists public.hr_payroll_run_lines (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  payroll_run_id uuid not null,
  employee_id uuid not null,
  employee_code_snapshot text not null,
  employee_name_snapshot text not null,
  employment_type_snapshot text not null check(employment_type_snapshot in ('monthly','hourly','contract')),
  base_gross_idr bigint not null check(base_gross_idr>=0),
  earnings_idr bigint not null default 0 check(earnings_idr>=0),
  gross_amount_idr bigint not null check(gross_amount_idr>=0),
  deductions_idr bigint not null default 0 check(deductions_idr>=0),
  employer_contributions_idr bigint not null default 0 check(employer_contributions_idr>=0),
  net_amount_idr bigint not null check(net_amount_idr>=0),
  components jsonb not null check(jsonb_typeof(components)='array'),
  profile_snapshot jsonb not null check(jsonb_typeof(profile_snapshot)='object'),
  calculation_hash_sha256 text not null check(calculation_hash_sha256 ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default now(),
  unique(tenant_id,id),
  unique(tenant_id,payroll_run_id,employee_id),
  foreign key(tenant_id,payroll_run_id) references public.hr_payroll_runs(tenant_id,id) on delete restrict,
  foreign key(tenant_id,employee_id) references public.hr_employees(tenant_id,id) on delete restrict,
  check(gross_amount_idr=base_gross_idr+earnings_idr),
  check(gross_amount_idr-deductions_idr=net_amount_idr)
);

create table if not exists public.finance_journal_batches (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  branch_id uuid not null,
  fiscal_period_id uuid not null references public.fiscal_periods(id) on delete restrict,
  source_type text not null,
  source_id uuid not null,
  status text not null default 'draft' check(status in ('draft','submitted','approved','posted','reversed')),
  currency text not null default 'IDR' check(currency='IDR'),
  debit_total_idr bigint not null check(debit_total_idr>=0),
  credit_total_idr bigint not null check(credit_total_idr>=0),
  idempotency_key text not null check(length(idempotency_key) between 8 and 160),
  created_by uuid not null references auth.users(id) on delete restrict,
  approved_by uuid null references auth.users(id) on delete restrict,
  approved_at timestamptz null,
  posted_at timestamptz null,
  created_at timestamptz not null default now(),
  unique(tenant_id,id),
  unique(tenant_id,idempotency_key),
  unique(tenant_id,source_type,source_id),
  foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict,
  check(debit_total_idr=credit_total_idr),
  check((status in ('approved','posted') and approved_by is not null and approved_at is not null and approved_by<>created_by) or status not in ('approved','posted'))
);

create table if not exists public.finance_journal_batch_lines (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  batch_id uuid not null,
  line_no integer not null check(line_no>0),
  account_code text not null,
  side text not null check(side in ('debit','credit')),
  amount_idr bigint not null check(amount_idr>0),
  component_code text null,
  description text not null,
  created_at timestamptz not null default now(),
  unique(tenant_id,id),
  unique(tenant_id,batch_id,line_no),
  foreign key(tenant_id,batch_id) references public.finance_journal_batches(tenant_id,id) on delete restrict
);

create table if not exists public.hr_payroll_payment_batches (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  branch_id uuid not null,
  payroll_run_id uuid not null,
  finance_batch_id uuid not null,
  provider_id text not null,
  status text not null default 'intent_created' check(status in ('intent_created','submitted','partially_settled','settled','failed','reversed','reconciled')),
  amount_idr bigint not null check(amount_idr>0),
  idempotency_key text not null check(length(idempotency_key) between 8 and 160),
  provider_reference text null,
  submitted_at timestamptz null,
  settled_at timestamptz null,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique(tenant_id,id),
  unique(tenant_id,idempotency_key),
  foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict,
  foreign key(tenant_id,payroll_run_id) references public.hr_payroll_runs(tenant_id,id) on delete restrict,
  foreign key(tenant_id,finance_batch_id) references public.finance_journal_batches(tenant_id,id) on delete restrict
);

create table if not exists public.hr_payroll_payment_items (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  payment_batch_id uuid not null,
  payroll_line_id uuid not null,
  beneficiary_reference_hash text not null check(beneficiary_reference_hash ~ '^[0-9a-f]{64}$'),
  amount_idr bigint not null check(amount_idr>0),
  status text not null default 'pending' check(status in ('pending','submitted','settled','failed','reversed')),
  provider_reference text null,
  settled_at timestamptz null,
  unique(tenant_id,id),
  unique(tenant_id,payment_batch_id,payroll_line_id),
  foreign key(tenant_id,payment_batch_id) references public.hr_payroll_payment_batches(tenant_id,id) on delete restrict,
  foreign key(tenant_id,payroll_line_id) references public.hr_payroll_run_lines(tenant_id,id) on delete restrict
);

create table if not exists public.finance_source_reconciliations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  branch_id uuid not null,
  source_type text not null,
  source_id uuid not null,
  journal_batch_id uuid not null,
  expected_amount_idr bigint not null check(expected_amount_idr>=0),
  posted_amount_idr bigint not null check(posted_amount_idr>=0),
  status text not null check(status in ('pending','reconciled','exception')),
  evidence_sha256 text not null check(evidence_sha256 ~ '^[0-9a-f]{64}$'),
  reconciled_by uuid null references auth.users(id) on delete restrict,
  reconciled_at timestamptz null,
  created_at timestamptz not null default now(),
  unique(tenant_id,id),
  unique(tenant_id,source_type,source_id),
  foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict,
  foreign key(tenant_id,journal_batch_id) references public.finance_journal_batches(tenant_id,id) on delete restrict,
  check((status='reconciled' and expected_amount_idr=posted_amount_idr and reconciled_by is not null and reconciled_at is not null) or status<>'reconciled')
);


-- Persist approved payroll snapshot and its balanced draft Finance batch atomically.
create or replace function public.hr_persist_approved_payroll_run(
  p_tenant_id uuid,
  p_branch_id uuid,
  p_payroll_run_id uuid,
  p_fiscal_period_id uuid,
  p_idempotency_key text,
  p_actor_user_id uuid,
  p_journal_lines jsonb
) returns jsonb
language plpgsql security invoker set search_path=''
as $$
declare
  v_run public.hr_payroll_runs%rowtype;
  v_period public.fiscal_periods%rowtype;
  v_existing public.finance_journal_batches%rowtype;
  v_batch public.finance_journal_batches%rowtype;
  v_employee_count integer;
  v_gross bigint;
  v_deductions bigint;
  v_employer bigint;
  v_net bigint;
  v_debits bigint;
  v_credits bigint;
  v_line_count integer;
begin
  if p_tenant_id is null or p_branch_id is null or p_payroll_run_id is null
     or p_fiscal_period_id is null or p_actor_user_id is null
     or length(coalesce(p_idempotency_key,'')) not between 8 and 160
     or jsonb_typeof(p_journal_lines)<>'array' then
    raise exception using errcode='22023',message='INVALID_PAYROLL_POST_COMMAND';
  end if;

  select * into v_run from public.hr_payroll_runs
   where tenant_id=p_tenant_id and branch_id=p_branch_id and id=p_payroll_run_id
   for update;
  if not found or v_run.status<>'approved' or v_run.approved_by is null
     or v_run.approved_at is null or v_run.approved_by=v_run.created_by then
    raise exception using errcode='23514',message='APPROVED_PAYROLL_RUN_REQUIRED';
  end if;

  select * into v_period from public.fiscal_periods where id=p_fiscal_period_id for update;
  if not found or v_period.status<>'open'
     or v_period.starts_on>v_run.period_start or v_period.ends_on<v_run.period_end then
    raise exception using errcode='23514',message='FISCAL_PERIOD_NOT_OPEN';
  end if;

  select count(*),coalesce(sum(gross_amount_idr),0),
         coalesce(sum(deductions_idr),0),coalesce(sum(employer_contributions_idr),0),
         coalesce(sum(net_amount_idr),0)
    into v_employee_count,v_gross,v_deductions,v_employer,v_net
    from public.hr_payroll_run_lines
   where tenant_id=p_tenant_id and payroll_run_id=p_payroll_run_id;
  if v_employee_count=0 or v_employee_count<>v_run.employee_count
     or v_gross<>v_run.gross_amount_idr or v_deductions<>v_run.deductions_amount_idr
     or v_employer<>v_run.employer_contributions_idr or v_net<>v_run.net_amount_idr
     or v_gross-v_deductions<>v_net then
    raise exception using errcode='23514',message='PAYROLL_LINE_SNAPSHOT_TOTAL_MISMATCH';
  end if;

  select * into v_existing from public.finance_journal_batches
   where tenant_id=p_tenant_id and idempotency_key=p_idempotency_key for update;
  if found then
    if v_existing.source_type<>'hr_payroll_run' or v_existing.source_id<>p_payroll_run_id
       or v_existing.debit_total_idr<>v_gross+v_employer
       or v_existing.credit_total_idr<>v_net+v_deductions+v_employer then
      raise exception using errcode='23505',message='PAYROLL_FINANCE_IDEMPOTENCY_COLLISION';
    end if;
    return jsonb_build_object('status','duplicate','batch_id',v_existing.id,
      'debit_total_idr',v_existing.debit_total_idr,'credit_total_idr',v_existing.credit_total_idr);
  end if;

  select count(*),
         coalesce(sum(case when x.side='debit' then x.amount_idr else 0 end),0),
         coalesce(sum(case when x.side='credit' then x.amount_idr else 0 end),0)
    into v_line_count,v_debits,v_credits
    from jsonb_to_recordset(p_journal_lines) as x(
      line_no integer,account_code text,side text,amount_idr bigint,
      component_code text,description text
    );
  if v_line_count=0 or exists(
    select 1 from jsonb_to_recordset(p_journal_lines) as x(
      line_no integer,account_code text,side text,amount_idr bigint,
      component_code text,description text
    )
    where x.line_no is null or x.line_no<=0 or nullif(btrim(x.account_code),'') is null
      or x.side not in ('debit','credit') or x.amount_idr is null or x.amount_idr<=0
      or nullif(btrim(x.description),'') is null
  ) or v_debits<>v_credits or v_debits<>v_gross+v_employer
     or v_credits<>v_net+v_deductions+v_employer then
    raise exception using errcode='23514',message='PAYROLL_JOURNAL_LINES_UNBALANCED';
  end if;

  insert into public.finance_journal_batches(
    tenant_id,branch_id,fiscal_period_id,source_type,source_id,status,currency,
    debit_total_idr,credit_total_idr,idempotency_key,created_by
  ) values(
    p_tenant_id,p_branch_id,p_fiscal_period_id,'hr_payroll_run',p_payroll_run_id,'draft','IDR',
    v_debits,v_credits,p_idempotency_key,p_actor_user_id
  ) returning * into v_batch;

  insert into public.finance_journal_batch_lines(
    tenant_id,batch_id,line_no,account_code,side,amount_idr,component_code,description
  )
  select p_tenant_id,v_batch.id,x.line_no,x.account_code,x.side,x.amount_idr,x.component_code,x.description
    from jsonb_to_recordset(p_journal_lines) as x(
      line_no integer,account_code text,side text,amount_idr bigint,
      component_code text,description text
    )
   order by x.line_no;

  insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
  values(p_actor_user_id,'hr.payroll.finance_batch_created','finance_journal_batches',v_batch.id::text,
    jsonb_build_object('tenant_id',p_tenant_id,'branch_id',p_branch_id,
      'payroll_run_id',p_payroll_run_id,'fiscal_period_id',p_fiscal_period_id,
      'debit_total_idr',v_debits,'credit_total_idr',v_credits,'line_count',v_line_count));
  return jsonb_build_object('status','draft','batch_id',v_batch.id,
    'debit_total_idr',v_debits,'credit_total_idr',v_credits,'line_count',v_line_count,
    'requires_independent_approval',true);
end;
$$;
revoke all on function public.hr_persist_approved_payroll_run(uuid,uuid,uuid,uuid,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.hr_persist_approved_payroll_run(uuid,uuid,uuid,uuid,text,uuid,jsonb) to service_role;

create or replace function public.hr_reject_payroll_snapshot_mutation()
returns trigger language plpgsql security invoker set search_path=''
as $$
begin
  raise exception using errcode='55000',message='PAYROLL_SNAPSHOT_IMMUTABLE';
end;
$$;
revoke all on function public.hr_reject_payroll_snapshot_mutation() from public,anon,authenticated;
drop trigger if exists hr_payroll_run_lines_immutable on public.hr_payroll_run_lines;
create trigger hr_payroll_run_lines_immutable before update or delete on public.hr_payroll_run_lines
for each row execute function public.hr_reject_payroll_snapshot_mutation();

do $$
declare t text;
begin
  foreach t in array array[
    'hr_employees','hr_payroll_profiles','hr_payroll_runs','hr_payroll_run_lines',
    'finance_journal_batches','finance_journal_batch_lines',
    'hr_payroll_payment_batches','hr_payroll_payment_items','finance_source_reconciliations'
  ] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('drop policy if exists service_role_only on public.%I',t);
    execute format('create policy service_role_only on public.%I for all to service_role using (true) with check (true)',t);
    execute format('revoke all on public.%I from anon, authenticated',t);
    execute format('grant select,insert,update,delete on public.%I to service_role',t);
  end loop;
end $$;
