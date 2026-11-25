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
