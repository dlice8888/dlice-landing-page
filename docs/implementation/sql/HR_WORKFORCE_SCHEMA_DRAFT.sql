-- DESIGN DRAFT ONLY — NOT A MIGRATION.
-- Uses the existing admin_profiles + branch_assignments identity foundation.
-- No production/staging schema change is performed by committing this file.
-- Every branch scope is joined to branches.tenant_id; branch_assignments itself
-- has no tenant_id in the inspected staging schema.
-- All writes remain behind authenticated Edge Function commands; no direct
-- anon/authenticated Data API access is granted.

create table if not exists public.hr_shift_schedules (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  branch_id uuid not null,
  employee_user_id uuid not null references auth.users(id) on delete restrict,
  job_position_id uuid not null references public.job_positions(id) on delete restrict,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  status text not null default 'scheduled' check (status in ('scheduled','confirmed','completed','cancelled','no_show')),
  notes text null,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id,id),
  foreign key (tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict,
  check (ends_at>starts_at)
);
create index if not exists hr_shift_schedules_employee_window_idx
  on public.hr_shift_schedules(tenant_id,employee_user_id,starts_at,ends_at);
create index if not exists hr_shift_schedules_branch_window_idx
  on public.hr_shift_schedules(tenant_id,branch_id,starts_at);

create table if not exists public.hr_attendance_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  branch_id uuid not null,
  employee_user_id uuid not null references auth.users(id) on delete restrict,
  event_type text not null check (event_type in ('clock_in','clock_out','break_start','break_end')),
  occurred_at timestamptz not null,
  source text not null check (source in ('kiosk','manager','mobile','system')),
  idempotency_key text not null check (length(idempotency_key) between 8 and 120),
  notes text null,
  recorded_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique (tenant_id,id),
  unique (tenant_id,idempotency_key),
  foreign key (tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict
);
create index if not exists hr_attendance_employee_time_idx
  on public.hr_attendance_events(tenant_id,employee_user_id,occurred_at desc);
create index if not exists hr_attendance_branch_time_idx
  on public.hr_attendance_events(tenant_id,branch_id,occurred_at desc);

create table if not exists public.hr_leave_requests (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  branch_id uuid not null,
  employee_user_id uuid not null references auth.users(id) on delete restrict,
  leave_type text not null check (leave_type in ('annual','sick','unpaid','maternity','paternity','other')),
  starts_on date not null,
  ends_on date not null,
  requested_days integer not null check (requested_days between 1 and 366),
  coverage_employee_user_id uuid null references auth.users(id) on delete restrict,
  coverage_approved boolean not null default false,
  status text not null default 'submitted' check (status in ('submitted','approved','rejected','cancelled')),
  reason text not null check (length(btrim(reason)) between 3 and 500),
  requested_by uuid not null references auth.users(id) on delete restrict,
  reviewed_by uuid null references auth.users(id) on delete restrict,
  reviewed_at timestamptz null,
  review_note text null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id,id),
  foreign key (tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict,
  check (ends_on>=starts_on),
  check (coverage_employee_user_id is null or coverage_employee_user_id<>employee_user_id),
  check (status<>'approved' or (coverage_employee_user_id is not null and coverage_approved=true and reviewed_by is not null))
);
create index if not exists hr_leave_branch_period_idx
  on public.hr_leave_requests(tenant_id,branch_id,starts_on,ends_on,status);
create index if not exists hr_leave_employee_period_idx
  on public.hr_leave_requests(tenant_id,employee_user_id,starts_on,ends_on);

create table if not exists public.hr_timesheets (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  branch_id uuid not null,
  employee_user_id uuid not null references auth.users(id) on delete restrict,
  period_start date not null,
  period_end date not null,
  total_minutes integer not null check (total_minutes>=0),
  attendance_event_ids uuid[] not null default '{}',
  status text not null default 'draft' check (status in ('draft','submitted','approved','rejected','locked')),
  submitted_at timestamptz null,
  approved_by uuid null references auth.users(id) on delete restrict,
  approved_at timestamptz null,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id,id),
  unique (tenant_id,employee_user_id,period_start,period_end),
  foreign key (tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict,
  check (period_end>=period_start),
  check (status<>'approved' or (approved_by is not null and approved_at is not null and approved_by<>employee_user_id)),
  check (status<>'submitted' or submitted_at is not null)
);
create index if not exists hr_timesheets_branch_period_idx
  on public.hr_timesheets(tenant_id,branch_id,period_start,period_end,status);

create table if not exists public.hr_payroll_runs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  period_start date not null,
  period_end date not null,
  currency text not null default 'IDR' check (currency='IDR'),
  gross_amount_idr bigint not null check (gross_amount_idr>=0),
  deductions_amount_idr bigint not null check (deductions_amount_idr>=0),
  net_amount_idr bigint generated always as (gross_amount_idr-deductions_amount_idr) stored,
  status text not null default 'draft' check (status in ('draft','approved','posted','cancelled')),
  idempotency_key text not null check (length(idempotency_key) between 8 and 120),
  created_by uuid not null references auth.users(id) on delete restrict,
  approved_by uuid null references auth.users(id) on delete restrict,
  posted_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id,id),
  unique (tenant_id,idempotency_key),
  check (period_end>=period_start),
  check (deductions_amount_idr<=gross_amount_idr),
  check (approved_by is null or approved_by<>created_by)
);
create index if not exists hr_payroll_period_idx
  on public.hr_payroll_runs(tenant_id,period_start,period_end,status);

create table if not exists public.hr_payroll_lines (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  payroll_run_id uuid not null,
  employee_user_id uuid not null references auth.users(id) on delete restrict,
  branch_id uuid not null,
  gross_amount_idr bigint not null check (gross_amount_idr>=0),
  deductions_amount_idr bigint not null check (deductions_amount_idr>=0),
  net_amount_idr bigint generated always as (gross_amount_idr-deductions_amount_idr) stored,
  source_timesheet_ids uuid[] not null default '{}',
  created_at timestamptz not null default now(),
  unique (tenant_id,id),
  unique (tenant_id,payroll_run_id,employee_user_id),
  foreign key (tenant_id,payroll_run_id) references public.hr_payroll_runs(tenant_id,id) on delete restrict,
  foreign key (tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict,
  check (deductions_amount_idr<=gross_amount_idr)
);

-- RLS/service-role-only is consistent with existing private ERP tables.
do $$
declare t text;
begin
  foreach t in array array[
    'hr_shift_schedules','hr_attendance_events','hr_leave_requests',
    'hr_timesheets','hr_payroll_runs','hr_payroll_lines'
  ] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('drop policy if exists service_role_only on public.%I',t);
    execute format('create policy service_role_only on public.%I for all to service_role using (true) with check (true)',t);
    execute format('revoke all on public.%I from anon, authenticated',t);
    execute format('grant select,insert,update,delete on public.%I to service_role',t);
  end loop;
end $$;

-- Append-only audit event for HR record creation and approvals.
create or replace function public.hr_audit_row_change()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row jsonb := to_jsonb(new);
  v_actor_id uuid;
  v_tenant_id uuid;
begin
  v_actor_id := nullif(coalesce(v_row->>'recorded_by',v_row->>'requested_by',v_row->>'approved_by',v_row->>'created_by'),'')::uuid;
  v_tenant_id := nullif(v_row->>'tenant_id','')::uuid;
  insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
  values (v_actor_id,'hr.'||tg_table_name||'.'||lower(tg_op),tg_table_name,v_row->>'id',
    jsonb_build_object('tenant_id',v_tenant_id,'branch_id',v_row->>'branch_id','employee_user_id',v_row->>'employee_user_id'));
  return new;
end;
$$;
revoke all on function public.hr_audit_row_change() from public,anon,authenticated;
drop trigger if exists hr_attendance_audit_insert on public.hr_attendance_events;
create trigger hr_attendance_audit_insert after insert on public.hr_attendance_events
for each row execute function public.hr_audit_row_change();
drop trigger if exists hr_leave_audit_change on public.hr_leave_requests;
create trigger hr_leave_audit_change after insert or update on public.hr_leave_requests
for each row execute function public.hr_audit_row_change();
drop trigger if exists hr_timesheet_audit_change on public.hr_timesheets;
create trigger hr_timesheet_audit_change after insert or update on public.hr_timesheets
for each row execute function public.hr_audit_row_change();
drop trigger if exists hr_payroll_audit_change on public.hr_payroll_runs;
create trigger hr_payroll_audit_change after insert or update on public.hr_payroll_runs
for each row execute function public.hr_audit_row_change();

-- Important: attendance and leave endpoints must verify an active tenant membership
-- AND an active branch_assignment for the employee before accepting a record.
-- Payroll posting must later write a balanced finance_journal_entries source reference
-- and reconcile approved timesheets before status may move to posted.
