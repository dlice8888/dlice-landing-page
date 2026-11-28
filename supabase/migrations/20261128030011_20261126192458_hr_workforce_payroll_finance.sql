-- D'Lice FnB OS official migration generated from reviewed domain SQL drafts.
-- Source files:
--   docs/implementation/sql/HR_WORKFORCE_SCHEMA_DRAFT.sql
--   docs/implementation/sql/HR_EMPLOYEE_LIFECYCLE_EXTENSION_DRAFT.sql
--   docs/implementation/sql/HR_PAYROLL_FINANCE_SCHEMA_DRAFT.sql
--   docs/implementation/sql/HR_PAYROLL_PAYMENT_ADAPTERS_DRAFT.sql

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
  check (status<>'approved' or (reviewed_by is not null and reviewed_by<>employee_user_id and (leave_type='sick' or (coverage_employee_user_id is not null and coverage_approved=true))))
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
  check (approved_by is null or approved_by<>created_by),
  check (status not in ('approved','posted') or approved_by is not null),
  check (status<>'posted' or posted_at is not null)
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
  created_by uuid not null references auth.users(id) on delete restrict,
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
  v_actor_id := nullif(coalesce(v_row->>'recorded_by',v_row->>'reviewed_by',v_row->>'approved_by',v_row->>'requested_by',v_row->>'created_by'),'')::uuid;
  v_tenant_id := nullif(v_row->>'tenant_id','')::uuid;
  insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
  values (v_actor_id,'hr.'||tg_table_name||'.'||lower(tg_op),tg_table_name,v_row->>'id',
    jsonb_build_object('tenant_id',v_tenant_id,'branch_id',v_row->>'branch_id','employee_user_id',v_row->>'employee_user_id'));
  return new;
end;
$$;
revoke all on function public.hr_audit_row_change() from public,anon,authenticated;
drop trigger if exists hr_schedule_audit_change on public.hr_shift_schedules;
create trigger hr_schedule_audit_change after insert or update on public.hr_shift_schedules
for each row execute function public.hr_audit_row_change();
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
drop trigger if exists hr_payroll_line_audit_insert on public.hr_payroll_lines;
create trigger hr_payroll_line_audit_insert after insert on public.hr_payroll_lines
for each row execute function public.hr_audit_row_change();

-- Transactional attendance command with per-employee/branch serialization.
create or replace function public.hr_record_attendance(
  p_tenant_id uuid,
  p_branch_id uuid,
  p_employee_user_id uuid,
  p_event_type text,
  p_source text,
  p_idempotency_key text,
  p_notes text,
  p_recorded_by uuid
) returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_last_event text;
  v_event public.hr_attendance_events%rowtype;
begin
  if p_event_type not in ('clock_in','clock_out','break_start','break_end')
    or p_source not in ('kiosk','manager','mobile','system')
    or length(coalesce(p_idempotency_key,'')) not between 8 and 120 then
    raise exception using errcode='22023', message='INVALID_ATTENDANCE_COMMAND';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||':'||p_branch_id::text||':'||p_employee_user_id::text,0));

  if exists(select 1 from public.hr_attendance_events where tenant_id=p_tenant_id and idempotency_key=p_idempotency_key) then
    raise exception using errcode='23505', message='DUPLICATE_ATTENDANCE_COMMAND';
  end if;

  if not exists(
    select 1 from public.branches b
    join public.tenant_memberships tm on tm.tenant_id=b.tenant_id and tm.user_id=p_employee_user_id and tm.status='active'
    join public.branch_assignments ba on ba.branch_id=b.id and ba.user_id=p_employee_user_id
      and ba.employment_status='active' and ba.starts_on<=current_date
      and (ba.ends_on is null or ba.ends_on>=current_date)
    join public.admin_profiles ap on ap.user_id=p_employee_user_id and ap.is_active=true
    where b.id=p_branch_id and b.tenant_id=p_tenant_id
  ) then
    raise exception using errcode='42501', message='EMPLOYEE_NOT_ASSIGNED_TO_BRANCH';
  end if;

  select event_type into v_last_event from public.hr_attendance_events
   where tenant_id=p_tenant_id and branch_id=p_branch_id and employee_user_id=p_employee_user_id
   order by occurred_at desc,created_at desc limit 1;

  if p_event_type='clock_in' and v_last_event is not null and v_last_event<>'clock_out' then
    raise exception using errcode='22023', message='ATTENDANCE_ALREADY_OPEN';
  elsif p_event_type='break_start' and (v_last_event is null or v_last_event not in ('clock_in','break_end')) then
    raise exception using errcode='22023', message='BREAK_START_REQUIRES_WORKING_STATE';
  elsif p_event_type='break_end' and (v_last_event is null or v_last_event<>'break_start') then
    raise exception using errcode='22023', message='BREAK_END_REQUIRES_OPEN_BREAK';
  elsif p_event_type='clock_out' and (v_last_event is null or v_last_event not in ('clock_in','break_end')) then
    raise exception using errcode='22023', message='CLOCK_OUT_REQUIRES_WORKING_STATE';
  end if;

  insert into public.hr_attendance_events
    (tenant_id,branch_id,employee_user_id,event_type,occurred_at,source,idempotency_key,notes,recorded_by)
  values
    (p_tenant_id,p_branch_id,p_employee_user_id,p_event_type,now(),p_source,p_idempotency_key,p_notes,p_recorded_by)
  returning * into v_event;

  return jsonb_build_object('id',v_event.id,'employee_user_id',v_event.employee_user_id,
    'event_type',v_event.event_type,'occurred_at',v_event.occurred_at,'source',v_event.source,'notes',v_event.notes);
end;
$$;
revoke all on function public.hr_record_attendance(uuid,uuid,uuid,text,text,text,text,uuid) from public,anon,authenticated;
grant execute on function public.hr_record_attendance(uuid,uuid,uuid,text,text,text,text,uuid) to service_role;

create or replace function public.hr_create_leave_request(
 p_tenant_id uuid,p_branch_id uuid,p_employee_user_id uuid,p_leave_type text,
 p_starts_on date,p_ends_on date,p_coverage_employee_user_id uuid,p_reason text,p_actor_user_id uuid
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v public.hr_leave_requests%rowtype;
begin
 if p_leave_type not in ('annual','sick','unpaid','maternity','paternity','other')
  or p_ends_on<p_starts_on or length(btrim(coalesce(p_reason,''))) not between 3 and 500 then
  raise exception using errcode='22023',message='INVALID_LEAVE_REQUEST';
 end if;
 if p_employee_user_id<>p_actor_user_id then raise exception using errcode='42501',message='EMPLOYEE_SELF_REQUEST_REQUIRED'; end if;
 if not exists(select 1 from public.branches b join public.tenant_memberships tm on tm.tenant_id=b.tenant_id and tm.user_id=p_employee_user_id and tm.status='active'
  join public.branch_assignments ba on ba.branch_id=b.id and ba.user_id=p_employee_user_id and ba.employment_status='active'
  join public.admin_profiles ap on ap.user_id=p_employee_user_id and ap.is_active=true
  where b.id=p_branch_id and b.tenant_id=p_tenant_id and ba.starts_on<=p_starts_on and (ba.ends_on is null or ba.ends_on>=p_ends_on)) then
  raise exception using errcode='42501',message='EMPLOYEE_NOT_ASSIGNED_FOR_LEAVE_PERIOD';
 end if;
 if p_leave_type<>'sick' and (p_coverage_employee_user_id is null or p_coverage_employee_user_id=p_employee_user_id) then
  raise exception using errcode='22023',message='SHIFT_COVERAGE_REQUIRED';
 end if;
 if exists(select 1 from public.hr_leave_requests where tenant_id=p_tenant_id and employee_user_id=p_employee_user_id
  and status in ('submitted','approved') and daterange(starts_on,ends_on,'[]') && daterange(p_starts_on,p_ends_on,'[]')) then
  raise exception using errcode='23505',message='LEAVE_PERIOD_OVERLAP';
 end if;
 insert into public.hr_leave_requests(tenant_id,branch_id,employee_user_id,leave_type,starts_on,ends_on,requested_days,
  coverage_employee_user_id,reason,requested_by)
 values(p_tenant_id,p_branch_id,p_employee_user_id,p_leave_type,p_starts_on,p_ends_on,(p_ends_on-p_starts_on+1),
  p_coverage_employee_user_id,btrim(p_reason),p_actor_user_id) returning * into v;
 return jsonb_build_object('leave_request_id',v.id,'status',v.status,'requested_days',v.requested_days);
end $$;
revoke all on function public.hr_create_leave_request(uuid,uuid,uuid,text,date,date,uuid,text,uuid) from public,anon,authenticated;
grant execute on function public.hr_create_leave_request(uuid,uuid,uuid,text,date,date,uuid,text,uuid) to service_role;

create or replace function public.hr_confirm_leave_coverage(p_leave_request_id uuid,p_actor_user_id uuid,p_approved boolean,p_note text)
returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v public.hr_leave_requests%rowtype;
begin
 select * into v from public.hr_leave_requests where id=p_leave_request_id for update;
 if not found then raise exception using errcode='P0002',message='LEAVE_REQUEST_NOT_FOUND'; end if;
 if v.status<>'submitted' or v.coverage_employee_user_id is null then raise exception using errcode='23514',message='LEAVE_COVERAGE_NOT_REQUIRED_OR_CLOSED'; end if;
 if v.coverage_employee_user_id<>p_actor_user_id then raise exception using errcode='42501',message='ONLY_COVERAGE_EMPLOYEE_CAN_CONFIRM'; end if;
 if p_approved and not exists(select 1 from public.branches b
  join public.tenant_memberships tm on tm.tenant_id=b.tenant_id and tm.user_id=p_actor_user_id and tm.status='active'
  join public.branch_assignments ba on ba.branch_id=b.id and ba.user_id=p_actor_user_id and ba.employment_status='active'
  join public.admin_profiles ap on ap.user_id=p_actor_user_id and ap.is_active=true
  where b.id=v.branch_id and b.tenant_id=v.tenant_id and ba.starts_on<=v.starts_on and (ba.ends_on is null or ba.ends_on>=v.ends_on)) then
  raise exception using errcode='42501',message='COVERAGE_EMPLOYEE_NOT_ASSIGNED_FOR_PERIOD';
 end if;
 update public.hr_leave_requests set coverage_approved=p_approved,review_note=left(coalesce(p_note,''),500),updated_at=now() where id=v.id;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,case when p_approved then 'hr.leave.coverage_accepted' else 'hr.leave.coverage_rejected' end,
 'hr_leave_request',v.id::text,jsonb_build_object('tenant_id',v.tenant_id,'employee_user_id',v.employee_user_id));
 return jsonb_build_object('leave_request_id',v.id,'coverage_approved',p_approved);
end $$;
revoke all on function public.hr_confirm_leave_coverage(uuid,uuid,boolean,text) from public,anon,authenticated;
grant execute on function public.hr_confirm_leave_coverage(uuid,uuid,boolean,text) to service_role;

create or replace function public.hr_review_leave_request(p_leave_request_id uuid,p_actor_user_id uuid,p_approve boolean,p_note text)
returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v public.hr_leave_requests%rowtype;
begin
 select * into v from public.hr_leave_requests where id=p_leave_request_id for update;
 if not found then raise exception using errcode='P0002',message='LEAVE_REQUEST_NOT_FOUND'; end if;
 if v.status<>'submitted' then raise exception using errcode='23514',message='LEAVE_REQUEST_NOT_SUBMITTED'; end if;
 if p_actor_user_id=v.employee_user_id or p_actor_user_id=v.requested_by then raise exception using errcode='42501',message='INDEPENDENT_LEAVE_REVIEW_REQUIRED'; end if;
 if p_approve and v.leave_type<>'sick' and (v.coverage_employee_user_id is null or v.coverage_approved is not true) then
  raise exception using errcode='23514',message='LEAVE_COVERAGE_NOT_CONFIRMED';
 end if;
 update public.hr_leave_requests set status=case when p_approve then 'approved' else 'rejected' end,
  reviewed_by=p_actor_user_id,reviewed_at=now(),review_note=left(coalesce(p_note,''),500),updated_at=now()
 where id=v.id returning * into v;
 return jsonb_build_object('leave_request_id',v.id,'status',v.status,'reviewed_by',v.reviewed_by);
end $$;
revoke all on function public.hr_review_leave_request(uuid,uuid,boolean,text) from public,anon,authenticated;
grant execute on function public.hr_review_leave_request(uuid,uuid,boolean,text) to service_role;

create or replace function public.hr_create_shift_schedule(
 p_tenant_id uuid,p_branch_id uuid,p_employee_user_id uuid,p_job_position_id uuid,
 p_starts_at timestamptz,p_ends_at timestamptz,p_created_by uuid,p_notes text
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v public.hr_shift_schedules%rowtype;
begin
 if p_ends_at<=p_starts_at then raise exception using errcode='22023',message='INVALID_SHIFT_WINDOW'; end if;
 if not exists(select 1 from public.branches b join public.tenant_memberships tm on tm.tenant_id=b.tenant_id and tm.user_id=p_employee_user_id and tm.status='active'
  join public.branch_assignments ba on ba.branch_id=b.id and ba.user_id=p_employee_user_id and ba.employment_status='active'
  where b.id=p_branch_id and b.tenant_id=p_tenant_id and ba.job_position_id=p_job_position_id
   and ba.starts_on<=p_starts_at::date and (ba.ends_on is null or ba.ends_on>=p_ends_at::date)) then
  raise exception using errcode='42501',message='EMPLOYEE_NOT_ASSIGNED_TO_BRANCH';
 end if;
 perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||':'||p_employee_user_id::text,0));
 if exists(select 1 from public.hr_shift_schedules where tenant_id=p_tenant_id and employee_user_id=p_employee_user_id
  and status in ('scheduled','confirmed') and tstzrange(starts_at,ends_at,'[)') && tstzrange(p_starts_at,p_ends_at,'[)')) then
  raise exception using errcode='23505',message='SHIFT_SCHEDULE_OVERLAP';
 end if;
 insert into public.hr_shift_schedules(tenant_id,branch_id,employee_user_id,job_position_id,starts_at,ends_at,created_by,notes)
 values(p_tenant_id,p_branch_id,p_employee_user_id,p_job_position_id,p_starts_at,p_ends_at,p_created_by,p_notes)
 returning * into v;
 return jsonb_build_object('shift_schedule_id',v.id,'status',v.status);
end $$;
revoke all on function public.hr_create_shift_schedule(uuid,uuid,uuid,uuid,timestamptz,timestamptz,uuid,text) from public,anon,authenticated;
grant execute on function public.hr_create_shift_schedule(uuid,uuid,uuid,uuid,timestamptz,timestamptz,uuid,text) to service_role;

create or replace function public.hr_generate_timesheet(
 p_tenant_id uuid,p_branch_id uuid,p_employee_user_id uuid,p_period_start date,p_period_end date,p_created_by uuid
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v_event record; v_state text:='off'; v_clock_in timestamptz; v_break_start timestamptz;
 v_minutes integer:=0; v_ids uuid[]:='{}'; v_count integer:=0; v_id uuid;
begin
 if p_period_end<p_period_start then raise exception using errcode='22023',message='INVALID_TIMESHEET_PERIOD'; end if;
 if not exists(select 1 from public.branches b join public.tenant_memberships tm on tm.tenant_id=b.tenant_id and tm.user_id=p_employee_user_id and tm.status='active'
  join public.branch_assignments ba on ba.branch_id=b.id and ba.user_id=p_employee_user_id and ba.employment_status='active'
  where b.id=p_branch_id and b.tenant_id=p_tenant_id) then raise exception using errcode='42501',message='EMPLOYEE_NOT_ASSIGNED_TO_BRANCH'; end if;
 for v_event in
  select id,event_type,occurred_at from public.hr_attendance_events
   where tenant_id=p_tenant_id and branch_id=p_branch_id and employee_user_id=p_employee_user_id
    and occurred_at>=p_period_start::timestamptz and occurred_at<(p_period_end+1)::timestamptz
   order by occurred_at,id
 loop
  v_ids:=array_append(v_ids,v_event.id);v_count:=v_count+1;
  if v_event.event_type='clock_in' and v_state='off' then v_clock_in:=v_event.occurred_at;v_state:='working';
  elsif v_event.event_type='break_start' and v_state='working' then v_break_start:=v_event.occurred_at;v_state:='break';
  elsif v_event.event_type='break_end' and v_state='break' then v_minutes:=v_minutes+greatest(0,floor(extract(epoch from (v_break_start-v_clock_in))/60)::integer);v_clock_in:=v_event.occurred_at;v_state:='working';
  elsif v_event.event_type='clock_out' and v_state='working' then v_minutes:=v_minutes+greatest(0,floor(extract(epoch from (v_event.occurred_at-v_clock_in))/60)::integer);v_state:='off';
  else raise exception using errcode='23514',message='INVALID_ATTENDANCE_SEQUENCE_IN_TIMESHEET';
  end if;
 end loop;
 if v_count=0 or v_state<>'off' then raise exception using errcode='23514',message='ATTENDANCE_EVIDENCE_INCOMPLETE'; end if;
 insert into public.hr_timesheets(tenant_id,branch_id,employee_user_id,period_start,period_end,total_minutes,attendance_event_ids,status,created_by)
 values(p_tenant_id,p_branch_id,p_employee_user_id,p_period_start,p_period_end,v_minutes,v_ids,'draft',p_created_by)
 returning id into v_id;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_created_by,'hr.timesheet.generated','hr_timesheet',v_id::text,jsonb_build_object('tenant_id',p_tenant_id,'branch_id',p_branch_id,'employee_user_id',p_employee_user_id,'total_minutes',v_minutes,'attendance_event_count',v_count));
 return jsonb_build_object('timesheet_id',v_id,'total_minutes',v_minutes,'attendance_event_count',v_count,'status','draft');
end $$;
revoke all on function public.hr_generate_timesheet(uuid,uuid,uuid,date,date,uuid) from public,anon,authenticated;
grant execute on function public.hr_generate_timesheet(uuid,uuid,uuid,date,date,uuid) to service_role;

create or replace function public.hr_submit_timesheet(p_timesheet_id uuid,p_actor_user_id uuid)
returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v public.hr_timesheets%rowtype;
begin
 select * into v from public.hr_timesheets where id=p_timesheet_id for update;
 if not found then raise exception using errcode='P0002',message='TIMESHEET_NOT_FOUND'; end if;
 if v.employee_user_id<>p_actor_user_id then raise exception using errcode='42501',message='ONLY_EMPLOYEE_CAN_SUBMIT_TIMESHEET'; end if;
 if v.status<>'draft' or cardinality(v.attendance_event_ids)=0 then raise exception using errcode='23514',message='TIMESHEET_NOT_SUBMITTABLE'; end if;
 update public.hr_timesheets set status='submitted',submitted_at=now(),updated_at=now() where id=v.id;
 return jsonb_build_object('timesheet_id',v.id,'status','submitted');
end $$;
revoke all on function public.hr_submit_timesheet(uuid,uuid) from public,anon,authenticated;
grant execute on function public.hr_submit_timesheet(uuid,uuid) to service_role;

create or replace function public.hr_approve_timesheet(p_timesheet_id uuid,p_actor_user_id uuid)
returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v public.hr_timesheets%rowtype;
begin
 select * into v from public.hr_timesheets where id=p_timesheet_id for update;
 if not found then raise exception using errcode='P0002',message='TIMESHEET_NOT_FOUND'; end if;
 if v.status<>'submitted' then raise exception using errcode='23514',message='TIMESHEET_NOT_SUBMITTED'; end if;
 if v.employee_user_id=p_actor_user_id then raise exception using errcode='42501',message='TIMESHEET_SELF_APPROVAL_FORBIDDEN'; end if;
 if exists(select 1 from unnest(v.attendance_event_ids) x(id) left join public.hr_attendance_events e on e.id=x.id and e.tenant_id=v.tenant_id and e.employee_user_id=v.employee_user_id and e.branch_id=v.branch_id where e.id is null) then
  raise exception using errcode='23514',message='TIMESHEET_ATTENDANCE_LINK_INVALID';
 end if;
 update public.hr_timesheets set status='approved',approved_by=p_actor_user_id,approved_at=now(),updated_at=now() where id=v.id;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'hr.timesheet.approved','hr_timesheet',v.id::text,jsonb_build_object('tenant_id',v.tenant_id,'employee_user_id',v.employee_user_id,'total_minutes',v.total_minutes));
 return jsonb_build_object('timesheet_id',v.id,'status','approved','total_minutes',v.total_minutes);
end $$;
revoke all on function public.hr_approve_timesheet(uuid,uuid) from public,anon,authenticated;
grant execute on function public.hr_approve_timesheet(uuid,uuid) to service_role;

-- Important: attendance and leave endpoints must verify an active tenant membership
-- AND an active branch_assignment for the employee before accepting a record.
-- Payroll posting must later write a balanced finance_journal_entries source reference
-- and reconcile approved timesheets before status may move to posted.

 
-- Payroll source-of-truth extension (reviewed migration).
-- Reuse the existing draft payroll tables above; extend them rather than
-- shadowing their established columns/constraints.
create table if not exists public.hr_compensation_rates (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete restrict,
 employee_user_id uuid not null references auth.users(id) on delete restrict,
 branch_id uuid not null,
 currency_code text not null default 'IDR' check(currency_code='IDR'),
 hourly_rate_idr bigint not null check(hourly_rate_idr>0),
 effective_from date not null,
 effective_to date null,
 approved_by uuid not null references auth.users(id) on delete restrict,
 approved_at timestamptz not null default now(),
 created_at timestamptz not null default now(),
 unique(tenant_id,id),
 foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict,
 check(effective_to is null or effective_to>=effective_from),
 check(approved_by<>employee_user_id)
);
create index if not exists hr_compensation_effective_lookup_idx
 on public.hr_compensation_rates(tenant_id,employee_user_id,branch_id,effective_from desc);

alter table public.hr_payroll_runs
 add column if not exists branch_id uuid,
 add column if not exists generated_by uuid references auth.users(id) on delete restrict,
 add column if not exists submitted_by uuid references auth.users(id) on delete restrict,
 add column if not exists approved_at timestamptz,
 add column if not exists posted_by uuid references auth.users(id) on delete restrict,
 add column if not exists finance_journal_id uuid,
 add column if not exists reconciliation_reference text;
alter table public.hr_payroll_runs drop constraint if exists hr_payroll_runs_status_check;
alter table public.hr_payroll_runs add constraint hr_payroll_runs_status_check
 check(status in ('draft','submitted','approved','posted','reconciled','cancelled'));
alter table public.hr_payroll_runs drop constraint if exists hr_payroll_runs_branch_scope_fk;
alter table public.hr_payroll_runs add constraint hr_payroll_runs_branch_scope_fk
 foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict;
alter table public.hr_payroll_runs drop constraint if exists hr_payroll_runs_approval_trace_check;
alter table public.hr_payroll_runs add constraint hr_payroll_runs_approval_trace_check
 check(status not in ('approved','posted','reconciled') or (approved_by is not null and approved_at is not null));
alter table public.hr_payroll_runs drop constraint if exists hr_payroll_runs_posting_trace_check;
alter table public.hr_payroll_runs add constraint hr_payroll_runs_posting_trace_check
 check(status not in ('posted','reconciled') or (posted_by is not null and posted_at is not null and finance_journal_id is not null));
alter table public.hr_payroll_runs drop constraint if exists hr_payroll_runs_reconciliation_trace_check;
alter table public.hr_payroll_runs add constraint hr_payroll_runs_reconciliation_trace_check
 check(status<>'reconciled' or reconciliation_reference is not null);

alter table public.hr_payroll_lines
 add column if not exists timesheet_id uuid,
 add column if not exists compensation_rate_id uuid,
 add column if not exists approved_minutes integer,
 add column if not exists hourly_rate_idr bigint;
alter table public.hr_payroll_lines drop constraint if exists hr_payroll_lines_timesheet_fk;
alter table public.hr_payroll_lines add constraint hr_payroll_lines_timesheet_fk
 foreign key(tenant_id,timesheet_id) references public.hr_timesheets(tenant_id,id) on delete restrict;
alter table public.hr_payroll_lines drop constraint if exists hr_payroll_lines_compensation_fk;
alter table public.hr_payroll_lines add constraint hr_payroll_lines_compensation_fk
 foreign key(tenant_id,compensation_rate_id) references public.hr_compensation_rates(tenant_id,id) on delete restrict;
create unique index if not exists hr_payroll_one_line_per_timesheet_uq
 on public.hr_payroll_lines(tenant_id,timesheet_id) where timesheet_id is not null;

-- Include new tables in the same private RLS posture as the existing HR draft.
alter table public.hr_compensation_rates enable row level security;
drop policy if exists service_role_only on public.hr_compensation_rates;
create policy service_role_only on public.hr_compensation_rates for all to service_role using(true) with check(true);
revoke all on public.hr_compensation_rates from anon,authenticated;
grant select,insert,update,delete on public.hr_compensation_rates to service_role;

create or replace function public.hr_generate_payroll_run(
 p_tenant_id uuid,p_branch_id uuid,p_period_start date,p_period_end date,p_actor_user_id uuid,p_idempotency_key text
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v_run public.hr_payroll_runs%rowtype; v_count integer; v_total bigint;
begin
 if p_period_end<p_period_start or length(coalesce(p_idempotency_key,'')) not between 8 and 120 then
  raise exception using errcode='22023',message='INVALID_PAYROLL_PERIOD_OR_IDEMPOTENCY_KEY';
 end if;
 if not exists(select 1 from public.branches where id=p_branch_id and tenant_id=p_tenant_id) then
  raise exception using errcode='42501',message='PAYROLL_BRANCH_TENANT_MISMATCH';
 end if;
 perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||':'||p_branch_id::text||':'||p_period_start::text||':'||p_period_end::text,0));
 if exists(select 1 from public.hr_payroll_runs where tenant_id=p_tenant_id and idempotency_key=p_idempotency_key) then
  raise exception using errcode='23505',message='PAYROLL_IDEMPOTENCY_KEY_REUSED';
 end if;
 if exists(select 1 from public.hr_payroll_runs where tenant_id=p_tenant_id and branch_id=p_branch_id
   and period_start=p_period_start and period_end=p_period_end and status in ('draft','submitted','approved')) then
  raise exception using errcode='23505',message='PAYROLL_RUN_ALREADY_EXISTS';
 end if;
 insert into public.hr_payroll_runs(tenant_id,period_start,period_end,currency,gross_amount_idr,deductions_amount_idr,status,idempotency_key,created_by,branch_id,generated_by)
 values(p_tenant_id,p_period_start,p_period_end,'IDR',0,0,'draft',p_idempotency_key,p_actor_user_id,p_branch_id,p_actor_user_id)
 returning * into v_run;
 insert into public.hr_payroll_lines(tenant_id,payroll_run_id,employee_user_id,branch_id,gross_amount_idr,deductions_amount_idr,source_timesheet_ids,created_by,timesheet_id,compensation_rate_id,approved_minutes,hourly_rate_idr)
 select t.tenant_id,v_run.id,t.employee_user_id,t.branch_id,
   round((t.total_minutes::numeric*r.hourly_rate_idr)/60)::bigint,0,array[t.id],p_actor_user_id,
   t.id,r.id,t.total_minutes,r.hourly_rate_idr
 from public.hr_timesheets t
 join lateral (
   select cr.id,cr.hourly_rate_idr from public.hr_compensation_rates cr
   where cr.tenant_id=t.tenant_id and cr.employee_user_id=t.employee_user_id and cr.branch_id=t.branch_id
    and cr.effective_from<=t.period_start and (cr.effective_to is null or cr.effective_to>=t.period_end)
   order by cr.effective_from desc limit 1
 ) r on true
 where t.tenant_id=p_tenant_id and t.branch_id=p_branch_id and t.status='approved'
  and t.period_start>=p_period_start and t.period_end<=p_period_end and t.total_minutes>0
  and not exists(select 1 from public.hr_payroll_lines old where old.tenant_id=t.tenant_id and old.timesheet_id=t.id);
 get diagnostics v_count=row_count;
 if v_count=0 then raise exception using errcode='23514',message='NO_APPROVED_TIMESHEETS_WITH_FULL_PERIOD_COMPENSATION'; end if;
 select coalesce(sum(gross_amount_idr),0) into v_total from public.hr_payroll_lines where tenant_id=p_tenant_id and payroll_run_id=v_run.id;
 update public.hr_payroll_runs set gross_amount_idr=v_total,updated_at=now() where id=v_run.id;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'hr.payroll.generated','hr_payroll_run',v_run.id::text,
  jsonb_build_object('tenant_id',p_tenant_id,'branch_id',p_branch_id,'line_count',v_count,'gross_total_idr',v_total,'period_start',p_period_start,'period_end',p_period_end));
 return jsonb_build_object('payroll_run_id',v_run.id,'status','draft','line_count',v_count,'gross_total_idr',v_total);
end $$;
revoke all on function public.hr_generate_payroll_run(uuid,uuid,date,date,uuid,text) from public,anon,authenticated;
grant execute on function public.hr_generate_payroll_run(uuid,uuid,date,date,uuid,text) to service_role;

create or replace function public.hr_submit_payroll_run(p_payroll_run_id uuid,p_actor_user_id uuid)
returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v public.hr_payroll_runs%rowtype;
begin
 select * into v from public.hr_payroll_runs where id=p_payroll_run_id for update;
 if not found then raise exception using errcode='P0002',message='PAYROLL_RUN_NOT_FOUND'; end if;
 if v.status<>'draft' or not exists(select 1 from public.hr_payroll_lines where tenant_id=v.tenant_id and payroll_run_id=v.id) then
  raise exception using errcode='23514',message='PAYROLL_RUN_NOT_SUBMITTABLE';
 end if;
 if p_actor_user_id in (v.created_by,v.generated_by) then raise exception using errcode='42501',message='INDEPENDENT_PAYROLL_SUBMITTER_REQUIRED'; end if;
 update public.hr_payroll_runs set status='submitted',submitted_by=p_actor_user_id,updated_at=now() where id=v.id;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'hr.payroll.submitted','hr_payroll_run',v.id::text,jsonb_build_object('tenant_id',v.tenant_id));
 return jsonb_build_object('payroll_run_id',v.id,'status','submitted');
end $$;
revoke all on function public.hr_submit_payroll_run(uuid,uuid) from public,anon,authenticated;
grant execute on function public.hr_submit_payroll_run(uuid,uuid) to service_role;

create or replace function public.hr_approve_payroll_run(p_payroll_run_id uuid,p_actor_user_id uuid)
returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v public.hr_payroll_runs%rowtype;
begin
 select * into v from public.hr_payroll_runs where id=p_payroll_run_id for update;
 if not found then raise exception using errcode='P0002',message='PAYROLL_RUN_NOT_FOUND'; end if;
 if v.status<>'submitted' then raise exception using errcode='23514',message='PAYROLL_RUN_NOT_SUBMITTED'; end if;
 if p_actor_user_id in (v.created_by,v.generated_by,v.submitted_by) then raise exception using errcode='42501',message='INDEPENDENT_PAYROLL_APPROVER_REQUIRED'; end if;
 update public.hr_payroll_runs set status='approved',approved_by=p_actor_user_id,approved_at=now(),updated_at=now() where id=v.id;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'hr.payroll.approved','hr_payroll_run',v.id::text,jsonb_build_object('tenant_id',v.tenant_id));
 return jsonb_build_object('payroll_run_id',v.id,'status','approved');
end $$;
revoke all on function public.hr_approve_payroll_run(uuid,uuid) from public,anon,authenticated;
grant execute on function public.hr_approve_payroll_run(uuid,uuid) to service_role;

-- No post RPC until the actual Finance journal schema, ACL and reconciliation
-- keys are confirmed. Never label an approved payroll as paid or posted.


-- Finance posting is owned by HR_PAYROLL_FINANCE_SCHEMA_DRAFT.sql.
-- No second payroll-finance outbox is created here; use the canonical
-- hr_payroll_finance_postings -> finance_journal_entries workflow.

create table if not exists public.hr_employee_records (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  employee_user_id uuid not null references auth.users(id) on delete restrict,
  employee_number text not null check(length(btrim(employee_number)) between 1 and 80),
  display_name_snapshot text null check(display_name_snapshot is null or length(display_name_snapshot)<=160),
  primary_branch_id uuid not null,
  job_position_id uuid not null references public.job_positions(id) on delete restrict,
  employment_status text not null default 'active'
    check(employment_status in ('active','on_leave','offboarding_pending','terminated')),
  hired_on date not null,
  terminated_on date null,
  created_by uuid not null references auth.users(id) on delete restrict,
  updated_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tenant_id,id),
  unique(tenant_id,employee_user_id),
  unique(tenant_id,employee_number),
  foreign key(tenant_id,primary_branch_id) references public.branches(tenant_id,id) on delete restrict,
  check((employment_status='terminated' and terminated_on is not null)
     or (employment_status<>'terminated' and terminated_on is null))
);
create index if not exists hr_employee_records_tenant_status_idx
  on public.hr_employee_records(tenant_id,employment_status,primary_branch_id);

create table if not exists public.hr_employee_lifecycle_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  employee_user_id uuid not null references auth.users(id) on delete restrict,
  branch_id uuid null,
  event_type text not null check(event_type in
    ('hire','transfer','position_change','leave_started','leave_ended','offboarding_requested','terminated','reactivated')),
  effective_on date not null,
  idempotency_key text not null check(length(idempotency_key) between 8 and 120),
  previous_state jsonb not null default '{}'::jsonb check(jsonb_typeof(previous_state)='object'),
  new_state jsonb not null default '{}'::jsonb check(jsonb_typeof(new_state)='object'),
  reason text not null check(length(btrim(reason)) between 3 and 500),
  related_leave_request_id uuid null,
  actor_user_id uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique(tenant_id,id),
  unique(tenant_id,idempotency_key),
  foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict,
  foreign key(tenant_id,related_leave_request_id) references public.hr_leave_requests(tenant_id,id) on delete restrict
);
create index if not exists hr_employee_lifecycle_employee_time_idx
  on public.hr_employee_lifecycle_events(tenant_id,employee_user_id,effective_on desc,created_at desc);

alter table public.hr_employee_records enable row level security;
alter table public.hr_employee_lifecycle_events enable row level security;
drop policy if exists service_role_only on public.hr_employee_records;
drop policy if exists service_role_only on public.hr_employee_lifecycle_events;
create policy service_role_only on public.hr_employee_records for all to service_role using(true) with check(true);
create policy service_role_only on public.hr_employee_lifecycle_events for all to service_role using(true) with check(true);
revoke all on public.hr_employee_records,public.hr_employee_lifecycle_events from public,anon,authenticated;
grant select,insert,update on public.hr_employee_records to service_role;
grant select,insert on public.hr_employee_lifecycle_events to service_role;

create or replace function public.hr_reject_employee_lifecycle_event_mutation()
returns trigger language plpgsql security invoker set search_path=''
as $$
begin
  raise exception using errcode='55000',message='HR_EMPLOYEE_LIFECYCLE_EVENTS_APPEND_ONLY';
end;
$$;
revoke all on function public.hr_reject_employee_lifecycle_event_mutation() from public,anon,authenticated;
drop trigger if exists hr_employee_lifecycle_events_append_only on public.hr_employee_lifecycle_events;
create trigger hr_employee_lifecycle_events_append_only
  before update or delete on public.hr_employee_lifecycle_events
  for each row execute function public.hr_reject_employee_lifecycle_event_mutation();

create or replace function public.hr_create_employee_record(
  p_tenant_id uuid,p_branch_id uuid,p_employee_user_id uuid,p_employee_number text,
  p_display_name_snapshot text,p_job_position_id uuid,p_hired_on date,
  p_idempotency_key text,p_actor_user_id uuid
) returns jsonb
language plpgsql security invoker set search_path=''
as $$
declare
  v_record public.hr_employee_records%rowtype;
  v_event public.hr_employee_lifecycle_events%rowtype;
begin
  if p_tenant_id is null or p_branch_id is null or p_employee_user_id is null
    or p_job_position_id is null or p_hired_on is null
    or length(btrim(coalesce(p_employee_number,''))) not between 1 and 80
    or length(coalesce(p_idempotency_key,'')) not between 8 and 120
    or length(btrim(coalesce(p_display_name_snapshot,'')))>160 then
    raise exception using errcode='22023',message='INVALID_HR_EMPLOYEE_CREATE';
  end if;
  if not exists(select 1 from public.admin_profiles ap where ap.user_id=p_actor_user_id and ap.is_active=true) then
    raise exception using errcode='42501',message='HR_EMPLOYEE_CREATOR_NOT_ACTIVE';
  end if;
  if p_actor_user_id=p_employee_user_id then raise exception using errcode='42501',message='INDEPENDENT_HR_EMPLOYEE_CREATOR_REQUIRED'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||':'||p_employee_user_id::text,0));
  select * into v_event from public.hr_employee_lifecycle_events
   where tenant_id=p_tenant_id and idempotency_key=p_idempotency_key;
  if found then
    if v_event.employee_user_id<>p_employee_user_id or v_event.event_type<>'hire'
       or v_event.branch_id<>p_branch_id or v_event.effective_on<>p_hired_on
       or v_event.new_state->>'employee_number'<>p_employee_number
       or v_event.new_state->>'job_position_id'<>p_job_position_id::text then
      raise exception using errcode='23505',message='HR_EMPLOYEE_CREATE_IDEMPOTENCY_COLLISION';
    end if;
    select * into v_record from public.hr_employee_records
     where tenant_id=p_tenant_id and employee_user_id=p_employee_user_id;
    return jsonb_build_object('status','duplicate','employee_id',v_record.id,'event_id',v_event.id);
  end if;
  if not exists(select 1 from public.branches b join public.tenant_memberships tm
    on tm.tenant_id=b.tenant_id and tm.user_id=p_employee_user_id and tm.status='active'
    join public.branch_assignments ba on ba.branch_id=b.id and ba.user_id=p_employee_user_id
      and ba.employment_status='active' and ba.starts_on<=p_hired_on
      and (ba.ends_on is null or ba.ends_on>=p_hired_on)
    join public.admin_profiles ap on ap.user_id=p_employee_user_id and ap.is_active=true
    join public.job_positions jp on jp.id=ba.job_position_id and jp.is_active=true
    where b.id=p_branch_id and b.tenant_id=p_tenant_id and ba.job_position_id=p_job_position_id) then
    raise exception using errcode='42501',message='EMPLOYEE_AUTH_MEMBERSHIP_ASSIGNMENT_REQUIRED';
  end if;
  insert into public.hr_employee_records(tenant_id,employee_user_id,employee_number,
    display_name_snapshot,primary_branch_id,job_position_id,employment_status,hired_on,created_by,updated_by)
  values(p_tenant_id,p_employee_user_id,btrim(p_employee_number),nullif(btrim(coalesce(p_display_name_snapshot,'')),''),
    p_branch_id,p_job_position_id,'active',p_hired_on,p_actor_user_id,p_actor_user_id)
  returning * into v_record;
  insert into public.hr_employee_lifecycle_events(tenant_id,employee_user_id,branch_id,event_type,
    effective_on,idempotency_key,previous_state,new_state,reason,actor_user_id)
  values(p_tenant_id,p_employee_user_id,p_branch_id,'hire',p_hired_on,p_idempotency_key,'{}'::jsonb,
    jsonb_build_object('employee_number',p_employee_number,'job_position_id',p_job_position_id,
      'employment_status','active'),'Employee lifecycle record created from existing authorized branch assignment',p_actor_user_id)
  returning * into v_event;
  insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
  values(p_actor_user_id,'hr.employee.hired','hr_employee_records',v_record.id::text,
    jsonb_build_object('tenant_id',p_tenant_id,'employee_user_id',p_employee_user_id,'branch_id',p_branch_id));
  return jsonb_build_object('status','created','employee_id',v_record.id,'event_id',v_event.id);
end;
$$;
revoke all on function public.hr_create_employee_record(uuid,uuid,uuid,text,text,uuid,date,text,uuid) from public,anon,authenticated;
grant execute on function public.hr_create_employee_record(uuid,uuid,uuid,text,text,uuid,date,text,uuid) to service_role;

create or replace function public.hr_apply_employee_lifecycle_event(
  p_tenant_id uuid,p_employee_user_id uuid,p_event_type text,p_effective_on date,
  p_new_branch_id uuid,p_new_job_position_id uuid,p_related_leave_request_id uuid,
  p_idempotency_key text,p_reason text,p_actor_user_id uuid
) returns jsonb
language plpgsql security invoker set search_path=''
as $$
declare
  v_record public.hr_employee_records%rowtype;
  v_event public.hr_employee_lifecycle_events%rowtype;
  v_leave public.hr_leave_requests%rowtype;
  v_previous jsonb;
  v_new jsonb;
  v_membership_role text;
  v_owner_count integer;
  v_pending_count integer;
  v_offboarding_actor uuid;
  v_branch uuid;
  v_position uuid;
begin
  if p_tenant_id is null or p_employee_user_id is null or p_event_type not in
    ('transfer','position_change','leave_started','leave_ended','offboarding_requested','terminated','reactivated')
    or p_effective_on is null or length(coalesce(p_idempotency_key,'')) not between 8 and 120
    or length(btrim(coalesce(p_reason,''))) not between 3 and 500 then
    raise exception using errcode='22023',message='INVALID_HR_LIFECYCLE_COMMAND';
  end if;
  if p_effective_on>current_date then raise exception using errcode='22023',message='FUTURE_DATED_LIFECYCLE_EVENT_REQUIRES_SCHEDULED_WORKER'; end if;
  if not exists(select 1 from public.admin_profiles ap where ap.user_id=p_actor_user_id and ap.is_active=true) then
    raise exception using errcode='42501',message='HR_LIFECYCLE_ACTOR_NOT_ACTIVE';
  end if;
  if p_actor_user_id=p_employee_user_id and p_event_type in ('transfer','position_change','offboarding_requested','terminated','reactivated') then
    raise exception using errcode='42501',message='INDEPENDENT_HR_LIFECYCLE_ACTOR_REQUIRED';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||':'||p_employee_user_id::text,0));
  select * into v_event from public.hr_employee_lifecycle_events
   where tenant_id=p_tenant_id and idempotency_key=p_idempotency_key;
  if found then
    if v_event.employee_user_id<>p_employee_user_id or v_event.event_type<>p_event_type
       or v_event.effective_on<>p_effective_on
       or (p_event_type in ('transfer','position_change','reactivated') and p_new_branch_id is not null and v_event.new_state->>'primary_branch_id'<>p_new_branch_id::text)
       or (p_event_type in ('transfer','position_change','reactivated') and p_new_job_position_id is not null and v_event.new_state->>'job_position_id'<>p_new_job_position_id::text) then
      raise exception using errcode='23505',message='HR_LIFECYCLE_IDEMPOTENCY_COLLISION';
    end if;
    return jsonb_build_object('status','duplicate','event_id',v_event.id,'event_type',v_event.event_type);
  end if;
  select * into v_record from public.hr_employee_records
   where tenant_id=p_tenant_id and employee_user_id=p_employee_user_id for update;
  if not found then raise exception using errcode='P0002',message='HR_EMPLOYEE_RECORD_NOT_FOUND'; end if;
  v_previous:=jsonb_build_object('employment_status',v_record.employment_status,
    'primary_branch_id',v_record.primary_branch_id,'job_position_id',v_record.job_position_id,
    'terminated_on',v_record.terminated_on);
  v_branch:=coalesce(p_new_branch_id,v_record.primary_branch_id);
  v_position:=coalesce(p_new_job_position_id,v_record.job_position_id);
  if p_event_type='transfer' and (p_new_branch_id is null or p_new_branch_id=v_record.primary_branch_id) then
    raise exception using errcode='22023',message='HR_TRANSFER_REQUIRES_DIFFERENT_TARGET_BRANCH';
  end if;
  if p_event_type='position_change' and (p_new_job_position_id is null or p_new_job_position_id=v_record.job_position_id) then
    raise exception using errcode='22023',message='HR_POSITION_CHANGE_REQUIRES_DIFFERENT_POSITION';
  end if;
  if p_event_type='reactivated' and (p_new_branch_id is null or p_new_job_position_id is null) then
    raise exception using errcode='22023',message='HR_REACTIVATION_REQUIRES_BRANCH_AND_POSITION';
  end if;

  if p_event_type in ('transfer','position_change','reactivated') then
    if not exists(select 1 from public.branches b join public.job_positions jp on jp.id=v_position and jp.is_active=true
      where b.id=v_branch and b.tenant_id=p_tenant_id) then
      raise exception using errcode='23503',message='HR_TARGET_BRANCH_OR_POSITION_INVALID';
    end if;
  end if;

  if p_event_type in ('transfer','position_change') then
    if v_record.employment_status<>'active' then
      raise exception using errcode='23514',message='HR_EMPLOYEE_NOT_TRANSFER_ELIGIBLE';
    end if;
    select count(*) into v_pending_count from public.hr_timesheets
     where tenant_id=p_tenant_id and employee_user_id=p_employee_user_id and status in ('draft','submitted');
    if v_pending_count>0 then raise exception using errcode='23514',message='HR_PENDING_TIMESHEETS_BLOCK_TRANSFER'; end if;
    if exists(select 1 from public.branch_assignments ba join public.branches b on b.id=ba.branch_id
      where b.tenant_id=p_tenant_id and ba.user_id=p_employee_user_id
        and ba.employment_status='active' and p_effective_on<=ba.starts_on) then
      raise exception using errcode='23514',message='HR_TRANSFER_EFFECTIVE_DATE_INVALID';
    end if;
    update public.hr_shift_schedules set status='cancelled',updated_at=now()
     where tenant_id=p_tenant_id and employee_user_id=p_employee_user_id
       and starts_at>=p_effective_on::timestamptz and status in ('scheduled','confirmed');
    update public.branch_assignments ba set employment_status='inactive',
      ends_on=p_effective_on-1,updated_at=now()
     from public.branches b
     where b.id=ba.branch_id and b.tenant_id=p_tenant_id and ba.user_id=p_employee_user_id
       and ba.employment_status in ('active','on_leave');
    insert into public.branch_assignments(branch_id,user_id,job_position_id,employment_status,starts_on,ends_on,assigned_by)
    values(v_branch,p_employee_user_id,v_position,'active',p_effective_on,null,p_actor_user_id);
    update public.hr_employee_records set primary_branch_id=v_branch,job_position_id=v_position,
      employment_status='active',updated_by=p_actor_user_id,updated_at=now()
     where tenant_id=p_tenant_id and employee_user_id=p_employee_user_id;
  elsif p_event_type='leave_started' then
    if v_record.employment_status<>'active' or p_related_leave_request_id is null then
      raise exception using errcode='23514',message='HR_APPROVED_LEAVE_REQUIRED';
    end if;
    select * into v_leave from public.hr_leave_requests
     where tenant_id=p_tenant_id and id=p_related_leave_request_id
       and employee_user_id=p_employee_user_id and status='approved' for update;
    if not found or p_effective_on not between v_leave.starts_on and v_leave.ends_on then
      raise exception using errcode='23514',message='HR_APPROVED_LEAVE_PERIOD_MISMATCH';
    end if;
    update public.hr_shift_schedules set status='cancelled',updated_at=now()
     where tenant_id=p_tenant_id and employee_user_id=p_employee_user_id
       and starts_at<v_leave.ends_on+1 and ends_at>=v_leave.starts_on
       and status in ('scheduled','confirmed');
    update public.branch_assignments ba set employment_status='on_leave',updated_at=now()
     from public.branches b where b.id=ba.branch_id and b.tenant_id=p_tenant_id
       and ba.user_id=p_employee_user_id and ba.employment_status='active';
    update public.hr_employee_records set employment_status='on_leave',updated_by=p_actor_user_id,updated_at=now()
     where tenant_id=p_tenant_id and employee_user_id=p_employee_user_id;
  elsif p_event_type='leave_ended' then
    if v_record.employment_status<>'on_leave' or p_related_leave_request_id is null then
      raise exception using errcode='23514',message='HR_LEAVE_NOT_OPEN';
    end if;
    select * into v_leave from public.hr_leave_requests
     where tenant_id=p_tenant_id and id=p_related_leave_request_id
       and employee_user_id=p_employee_user_id and status='approved' for update;
    if not found or p_effective_on<=v_leave.ends_on then
      raise exception using errcode='23514',message='HR_LEAVE_RETURN_DATE_INVALID';
    end if;
    update public.branch_assignments ba set employment_status='active',updated_at=now()
     from public.branches b where b.id=ba.branch_id and b.tenant_id=p_tenant_id
       and ba.user_id=p_employee_user_id and ba.employment_status='on_leave';
    update public.hr_employee_records set employment_status='active',updated_by=p_actor_user_id,updated_at=now()
     where tenant_id=p_tenant_id and employee_user_id=p_employee_user_id;
  elsif p_event_type='offboarding_requested' then
    if v_record.employment_status<>'active' then
      raise exception using errcode='23514',message='HR_OFFBOARDING_NOT_ELIGIBLE';
    end if;
    update public.hr_employee_records set employment_status='offboarding_pending',updated_by=p_actor_user_id,updated_at=now()
     where tenant_id=p_tenant_id and employee_user_id=p_employee_user_id;
  elsif p_event_type='terminated' then
    if v_record.employment_status<>'offboarding_pending' then
      raise exception using errcode='23514',message='HR_OFFBOARDING_APPROVAL_REQUIRED';
    end if;
    select actor_user_id into v_offboarding_actor from public.hr_employee_lifecycle_events
     where tenant_id=p_tenant_id and employee_user_id=p_employee_user_id and event_type='offboarding_requested'
     order by created_at desc limit 1;
    if v_offboarding_actor is null or v_offboarding_actor=p_actor_user_id then
      raise exception using errcode='42501',message='INDEPENDENT_OFFBOARDING_APPROVER_REQUIRED';
    end if;
    select count(*) into v_pending_count from public.hr_timesheets
     where tenant_id=p_tenant_id and employee_user_id=p_employee_user_id and status in ('draft','submitted');
    if v_pending_count>0 then raise exception using errcode='23514',message='HR_PENDING_TIMESHEETS_BLOCK_TERMINATION'; end if;
    if exists(select 1 from public.hr_leave_requests where tenant_id=p_tenant_id and employee_user_id=p_employee_user_id
      and status in ('submitted','approved') and ends_on>=current_date) then
      raise exception using errcode='23514',message='HR_OPEN_LEAVE_BLOCKS_TERMINATION';
    end if;
    select role into v_membership_role from public.tenant_memberships
     where tenant_id=p_tenant_id and user_id=p_employee_user_id and status='active' for update;
    if v_membership_role is null then raise exception using errcode='23514',message='HR_ACTIVE_TENANT_MEMBERSHIP_REQUIRED'; end if;
    if v_membership_role='tenant_owner' then
      select count(*) into v_owner_count from public.tenant_memberships
       where tenant_id=p_tenant_id and role='tenant_owner' and status='active';
      if v_owner_count<=1 then raise exception using errcode='23514',message='HR_CANNOT_REVOKE_LAST_TENANT_OWNER'; end if;
    end if;
    update public.hr_shift_schedules set status='cancelled',updated_at=now()
     where tenant_id=p_tenant_id and employee_user_id=p_employee_user_id
       and starts_at>=p_effective_on::timestamptz and status in ('scheduled','confirmed');
    update public.branch_assignments ba set employment_status='inactive',
      ends_on=greatest(ba.starts_on,p_effective_on),updated_at=now()
     from public.branches b where b.id=ba.branch_id and b.tenant_id=p_tenant_id
       and ba.user_id=p_employee_user_id and ba.employment_status in ('active','on_leave');
    update public.tenant_memberships set status='revoked',updated_at=now()
     where tenant_id=p_tenant_id and user_id=p_employee_user_id and status='active';
    update public.hr_employee_records set employment_status='terminated',terminated_on=p_effective_on,
      updated_by=p_actor_user_id,updated_at=now()
     where tenant_id=p_tenant_id and employee_user_id=p_employee_user_id;
  elsif p_event_type='reactivated' then
    if v_record.employment_status<>'terminated' then
      raise exception using errcode='23514',message='HR_EMPLOYEE_NOT_TERMINATED';
    end if;
    if not exists(select 1 from public.admin_profiles ap where ap.user_id=p_employee_user_id and ap.is_active=true) then
      raise exception using errcode='42501',message='HR_AUTH_PROFILE_MUST_BE_REACTIVATED_FIRST';
    end if;
    update public.tenant_memberships set status='active',updated_at=now()
     where tenant_id=p_tenant_id and user_id=p_employee_user_id and status='revoked';
    if not found then raise exception using errcode='P0002',message='HR_REVOKED_TENANT_MEMBERSHIP_NOT_FOUND'; end if;
    insert into public.branch_assignments(branch_id,user_id,job_position_id,employment_status,starts_on,ends_on,assigned_by)
    values(v_branch,p_employee_user_id,v_position,'active',p_effective_on,null,p_actor_user_id);
    update public.hr_employee_records set primary_branch_id=v_branch,job_position_id=v_position,
      employment_status='active',terminated_on=null,updated_by=p_actor_user_id,updated_at=now()
     where tenant_id=p_tenant_id and employee_user_id=p_employee_user_id;
  end if;

  select * into v_record from public.hr_employee_records
   where tenant_id=p_tenant_id and employee_user_id=p_employee_user_id;
  v_new:=jsonb_build_object('employment_status',v_record.employment_status,
    'primary_branch_id',v_record.primary_branch_id,'job_position_id',v_record.job_position_id,
    'terminated_on',v_record.terminated_on);
  insert into public.hr_employee_lifecycle_events(tenant_id,employee_user_id,branch_id,event_type,
    effective_on,idempotency_key,previous_state,new_state,reason,related_leave_request_id,actor_user_id)
  values(p_tenant_id,p_employee_user_id,v_record.primary_branch_id,p_event_type,p_effective_on,
    p_idempotency_key,v_previous,v_new,btrim(p_reason),p_related_leave_request_id,p_actor_user_id)
  returning * into v_event;
  insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
  values(p_actor_user_id,'hr.employee.'||p_event_type,'hr_employee_lifecycle_event',v_event.id::text,
    jsonb_build_object('tenant_id',p_tenant_id,'employee_user_id',p_employee_user_id,
      'previous_state',v_previous,'new_state',v_new,'effective_on',p_effective_on));
  return jsonb_build_object('status','applied','event_id',v_event.id,
    'event_type',p_event_type,'employee_status',v_record.employment_status);
end;
$$;
revoke all on function public.hr_apply_employee_lifecycle_event(uuid,uuid,text,date,uuid,uuid,uuid,text,text,uuid) from public,anon,authenticated;
grant execute on function public.hr_apply_employee_lifecycle_event(uuid,uuid,text,date,uuid,uuid,uuid,text,text,uuid) to service_role;

create table if not exists public.hr_payroll_finance_account_mappings (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  branch_id uuid not null,
  payroll_expense_account text not null check(length(btrim(payroll_expense_account)) between 1 and 80),
  payroll_payable_account text not null check(length(btrim(payroll_payable_account)) between 1 and 80),
  payroll_deduction_account text not null check(length(btrim(payroll_deduction_account)) between 1 and 80),
  status text not null default 'pending' check(status in ('pending','approved','suspended')),
  created_by uuid not null references auth.users(id) on delete restrict,
  approved_by uuid null references auth.users(id) on delete restrict,
  approved_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tenant_id,id),
  unique(tenant_id,branch_id),
  foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict,
  check((status='approved' and approved_by is not null and approved_at is not null and approved_by<>created_by) or status<>'approved')
);

create table if not exists public.hr_payroll_finance_postings (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  branch_id uuid not null,
  payroll_run_id uuid not null,
  fiscal_period_id uuid not null references public.fiscal_periods(id) on delete restrict,
  status text not null default 'draft' check(status in ('draft','posted','reconciled','exception')),
  gross_amount_idr bigint not null check(gross_amount_idr>0),
  deductions_amount_idr bigint not null check(deductions_amount_idr>=0),
  net_amount_idr bigint not null check(net_amount_idr>=0),
  finance_entry_ids uuid[] not null default '{}',
  idempotency_key text not null check(length(idempotency_key) between 8 and 160),
  created_by uuid not null references auth.users(id) on delete restrict,
  posted_by uuid null references auth.users(id) on delete restrict,
  posted_at timestamptz null,
  reconciled_by uuid null references auth.users(id) on delete restrict,
  reconciled_at timestamptz null,
  reconciliation_sha256 text null check(reconciliation_sha256 is null or reconciliation_sha256 ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tenant_id,id),
  unique(tenant_id,payroll_run_id),
  unique(tenant_id,idempotency_key),
  foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict,
  foreign key(tenant_id,payroll_run_id) references public.hr_payroll_runs(tenant_id,id) on delete restrict,
  check(gross_amount_idr-deductions_amount_idr=net_amount_idr),
  check((status in ('posted','reconciled') and posted_by is not null and posted_at is not null and cardinality(finance_entry_ids)>0) or status not in ('posted','reconciled')),
  check((status='reconciled' and reconciled_by is not null and reconciled_at is not null and reconciliation_sha256 is not null) or status<>'reconciled')
);

alter table public.hr_payroll_runs
  add column if not exists finance_journal_id uuid;
alter table public.hr_payroll_runs drop constraint if exists hr_payroll_runs_finance_posting_fk;
alter table public.hr_payroll_runs add constraint hr_payroll_runs_finance_posting_fk
  foreign key(tenant_id,finance_journal_id)
  references public.hr_payroll_finance_postings(tenant_id,id) on delete restrict;

create index if not exists hr_payroll_finance_posting_period_idx
  on public.hr_payroll_finance_postings(tenant_id,branch_id,status,created_at desc);
create index if not exists hr_payroll_finance_entry_source_idx
  on public.finance_journal_entries(source_type,source_id,status)
  where source_type='hr_payroll_run';

create or replace function public.hr_approve_payroll_finance_mapping(
  p_tenant_id uuid,p_mapping_id uuid,p_actor_user_id uuid
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v public.hr_payroll_finance_account_mappings%rowtype;
begin
  select * into v from public.hr_payroll_finance_account_mappings
   where tenant_id=p_tenant_id and id=p_mapping_id for update;
  if not found then raise exception using errcode='P0002',message='PAYROLL_FINANCE_MAPPING_NOT_FOUND'; end if;
  if v.status<>'pending' or v.created_by=p_actor_user_id then
    raise exception using errcode='42501',message='INDEPENDENT_PAYROLL_FINANCE_MAPPING_APPROVAL_REQUIRED';
  end if;
  update public.hr_payroll_finance_account_mappings
    set status='approved',approved_by=p_actor_user_id,approved_at=now(),updated_at=now()
    where id=v.id returning * into v;
  insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
  values(p_actor_user_id,'hr.payroll.finance_mapping_approved','hr_payroll_finance_account_mappings',v.id::text,
    jsonb_build_object('tenant_id',p_tenant_id,'branch_id',v.branch_id));
  return jsonb_build_object('mapping_id',v.id,'status',v.status);
end;
$$;
revoke all on function public.hr_approve_payroll_finance_mapping(uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.hr_approve_payroll_finance_mapping(uuid,uuid,uuid) to service_role;

-- Prepare balanced draft journal rows against the REAL finance_journal_entries
-- model. Each row is a debit/credit pair; net pay + deductions equals gross.
create or replace function public.hr_prepare_payroll_finance_posting(
  p_tenant_id uuid,p_branch_id uuid,p_payroll_run_id uuid,p_fiscal_period_id uuid,
  p_idempotency_key text,p_actor_user_id uuid
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare
  v_run public.hr_payroll_runs%rowtype;
  v_period public.fiscal_periods%rowtype;
  v_map public.hr_payroll_finance_account_mappings%rowtype;
  v_post public.hr_payroll_finance_postings%rowtype;
  v_line record;
  v_gross bigint;
  v_deductions bigint;
  v_net bigint;
  v_line_no integer:=0;
  v_entry_id uuid;
  v_ids uuid[]:='{}';
  v_entry_code text;
begin
  if length(coalesce(p_idempotency_key,'')) not between 8 and 160 then
    raise exception using errcode='22023',message='INVALID_PAYROLL_FINANCE_IDEMPOTENCY_KEY';
  end if;
  select * into v_run from public.hr_payroll_runs
   where tenant_id=p_tenant_id and branch_id=p_branch_id and id=p_payroll_run_id for update;
  if not found or v_run.status<>'approved' or v_run.approved_by is null
     or v_run.approved_at is null or v_run.approved_by in (v_run.created_by,v_run.generated_by,v_run.submitted_by) then
    raise exception using errcode='23514',message='INDEPENDENTLY_APPROVED_PAYROLL_RUN_REQUIRED';
  end if;
  select * into v_period from public.fiscal_periods where id=p_fiscal_period_id for update;
  if not found or v_period.status<>'open'
     or v_period.starts_on>v_run.period_start or v_period.ends_on<v_run.period_end then
    raise exception using errcode='23514',message='OPEN_FISCAL_PERIOD_REQUIRED';
  end if;
  select * into v_map from public.hr_payroll_finance_account_mappings
   where tenant_id=p_tenant_id and branch_id=p_branch_id and status='approved' for share;
  if not found then raise exception using errcode='P0002',message='APPROVED_PAYROLL_FINANCE_ACCOUNT_MAPPING_REQUIRED'; end if;
  select coalesce(sum(gross_amount_idr),0),coalesce(sum(deductions_amount_idr),0),
         coalesce(sum(net_amount_idr),0)
    into v_gross,v_deductions,v_net
    from public.hr_payroll_lines where tenant_id=p_tenant_id and payroll_run_id=p_payroll_run_id;
  if v_gross<=0 or v_gross<>v_run.gross_amount_idr
     or v_deductions<>v_run.deductions_amount_idr
     or v_net<>v_run.net_amount_idr or v_gross-v_deductions<>v_net then
    raise exception using errcode='23514',message='PAYROLL_LINES_DO_NOT_RECONCILE_TO_RUN';
  end if;
  select * into v_post from public.hr_payroll_finance_postings
   where tenant_id=p_tenant_id and payroll_run_id=p_payroll_run_id for update;
  if found then
    if v_post.idempotency_key<>p_idempotency_key or v_post.gross_amount_idr<>v_gross then
      raise exception using errcode='23505',message='PAYROLL_FINANCE_POSTING_ALREADY_EXISTS';
    end if;
    return jsonb_build_object('status',v_post.status,'posting_id',v_post.id,'finance_entry_ids',v_post.finance_entry_ids);
  end if;
  insert into public.hr_payroll_finance_postings(
    tenant_id,branch_id,payroll_run_id,fiscal_period_id,status,gross_amount_idr,
    deductions_amount_idr,net_amount_idr,idempotency_key,created_by
  ) values(p_tenant_id,p_branch_id,p_payroll_run_id,p_fiscal_period_id,'draft',
    v_gross,v_deductions,v_net,p_idempotency_key,p_actor_user_id)
  returning * into v_post;

  for v_line in
    select id,employee_user_id,gross_amount_idr,deductions_amount_idr,net_amount_idr
      from public.hr_payroll_lines
     where tenant_id=p_tenant_id and payroll_run_id=p_payroll_run_id
     order by employee_user_id,id
  loop
    if v_line.net_amount_idr>0 then
      v_line_no:=v_line_no+1;
      v_entry_code:='PAY-'||replace(p_payroll_run_id::text,'-','')||'-'||lpad(v_line_no::text,5,'0');
      insert into public.finance_journal_entries(
        entry_code,fiscal_period_id,branch_id,source_type,source_id,entry_date,
        debit_account,credit_account,amount_idr,description,status,created_by
      ) values(v_entry_code,p_fiscal_period_id,p_branch_id,'hr_payroll_run',p_payroll_run_id,
        v_run.period_end,v_map.payroll_expense_account,v_map.payroll_payable_account,
        v_line.net_amount_idr,'Payroll net payable line '||v_line.id::text,'draft',p_actor_user_id)
      returning id into v_entry_id;
      v_ids:=array_append(v_ids,v_entry_id);
    end if;
    if v_line.deductions_amount_idr>0 then
      v_line_no:=v_line_no+1;
      v_entry_code:='PAY-'||replace(p_payroll_run_id::text,'-','')||'-'||lpad(v_line_no::text,5,'0');
      insert into public.finance_journal_entries(
        entry_code,fiscal_period_id,branch_id,source_type,source_id,entry_date,
        debit_account,credit_account,amount_idr,description,status,created_by
      ) values(v_entry_code,p_fiscal_period_id,p_branch_id,'hr_payroll_run',p_payroll_run_id,
        v_run.period_end,v_map.payroll_expense_account,v_map.payroll_deduction_account,
        v_line.deductions_amount_idr,'Payroll deductions line '||v_line.id::text,'draft',p_actor_user_id)
      returning id into v_entry_id;
      v_ids:=array_append(v_ids,v_entry_id);
    end if;
  end loop;
  if cardinality(v_ids)=0 then raise exception using errcode='23514',message='PAYROLL_JOURNAL_HAS_NO_LINES'; end if;
  update public.hr_payroll_finance_postings set finance_entry_ids=v_ids,updated_at=now() where id=v_post.id;
  update public.hr_payroll_runs set finance_journal_id=v_post.id,updated_at=now() where id=v_run.id;
  insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
  values(p_actor_user_id,'hr.payroll.finance_posting_prepared','hr_payroll_finance_postings',v_post.id::text,
    jsonb_build_object('tenant_id',p_tenant_id,'branch_id',p_branch_id,'payroll_run_id',p_payroll_run_id,
      'gross_idr',v_gross,'deductions_idr',v_deductions,'net_idr',v_net,'journal_entry_count',cardinality(v_ids)));
  return jsonb_build_object('status','draft','posting_id',v_post.id,'finance_entry_ids',v_ids,
    'gross_amount_idr',v_gross,'deductions_amount_idr',v_deductions,'net_amount_idr',v_net);
end;
$$;
revoke all on function public.hr_prepare_payroll_finance_posting(uuid,uuid,uuid,uuid,text,uuid) from public,anon,authenticated;
grant execute on function public.hr_prepare_payroll_finance_posting(uuid,uuid,uuid,uuid,text,uuid) to service_role;

create or replace function public.hr_post_payroll_finance_posting(
  p_tenant_id uuid,p_posting_id uuid,p_actor_user_id uuid
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v public.hr_payroll_finance_postings%rowtype; r public.hr_payroll_runs%rowtype;
begin
  select * into v from public.hr_payroll_finance_postings
   where tenant_id=p_tenant_id and id=p_posting_id for update;
  if not found or v.status<>'draft' then raise exception using errcode='23514',message='PAYROLL_FINANCE_DRAFT_REQUIRED'; end if;
  select * into r from public.hr_payroll_runs
   where tenant_id=p_tenant_id and id=v.payroll_run_id for update;
  if not found or r.status<>'approved' or p_actor_user_id in (v.created_by,r.created_by,r.generated_by,r.submitted_by,r.approved_by) then
    raise exception using errcode='42501',message='INDEPENDENT_PAYROLL_FINANCE_POSTER_REQUIRED';
  end if;
  if exists(select 1 from public.fiscal_periods where id=v.fiscal_period_id and status<>'open') then
    raise exception using errcode='23514',message='FISCAL_PERIOD_CLOSED_BEFORE_POSTING';
  end if;
  if cardinality(v.finance_entry_ids)=0 or exists(
    select 1 from public.finance_journal_entries e
     where e.id=any(v.finance_entry_ids) and (e.status<>'draft' or e.source_type<>'hr_payroll_run' or e.source_id<>r.id or e.branch_id<>v.branch_id or e.fiscal_period_id<>v.fiscal_period_id)
  ) or (select count(*) from public.finance_journal_entries e where e.id=any(v.finance_entry_ids))<>cardinality(v.finance_entry_ids)
    or (select coalesce(sum(e.amount_idr),0) from public.finance_journal_entries e where e.id=any(v.finance_entry_ids))<>v.gross_amount_idr then
    raise exception using errcode='23514',message='PAYROLL_FINANCE_DRAFT_ENTRIES_CHANGED';
  end if;
  update public.finance_journal_entries set status='posted' where id=any(v.finance_entry_ids);
  update public.hr_payroll_finance_postings set status='posted',posted_by=p_actor_user_id,posted_at=now(),updated_at=now()
   where id=v.id returning * into v;
  update public.hr_payroll_runs set status='posted',posted_by=p_actor_user_id,posted_at=now(),updated_at=now()
   where id=r.id;
  insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
  values(p_actor_user_id,'hr.payroll.finance_posted','hr_payroll_finance_postings',v.id::text,
    jsonb_build_object('tenant_id',p_tenant_id,'payroll_run_id',r.id,'finance_entry_ids',v.finance_entry_ids));
  return jsonb_build_object('status','posted','posting_id',v.id,'payroll_run_id',r.id,'finance_entry_ids',v.finance_entry_ids);
end;
$$;
revoke all on function public.hr_post_payroll_finance_posting(uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.hr_post_payroll_finance_posting(uuid,uuid,uuid) to service_role;

create or replace function public.hr_reconcile_payroll_finance_posting(
  p_tenant_id uuid,p_posting_id uuid,p_actor_user_id uuid
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare
  v public.hr_payroll_finance_postings%rowtype;
  r public.hr_payroll_runs%rowtype;
  v_count integer;
  v_amount bigint;
  v_evidence jsonb;
  v_hash text;
begin
  select * into v from public.hr_payroll_finance_postings
   where tenant_id=p_tenant_id and id=p_posting_id for update;
  if not found or v.status<>'posted' then
    raise exception using errcode='23514',message='POSTED_PAYROLL_FINANCE_REQUIRED';
  end if;
  select * into r from public.hr_payroll_runs
   where tenant_id=p_tenant_id and id=v.payroll_run_id for update;
  if not found then raise exception using errcode='23503',message='PAYROLL_RUN_SOURCE_MISSING'; end if;
  if p_actor_user_id in (v.created_by,v.posted_by,r.created_by,r.generated_by,r.submitted_by,r.approved_by) then
    raise exception using errcode='42501',message='INDEPENDENT_PAYROLL_RECONCILER_REQUIRED';
  end if;
  select count(*),coalesce(sum(amount_idr),0) into v_count,v_amount
    from public.finance_journal_entries
   where id=any(v.finance_entry_ids) and source_type='hr_payroll_run'
     and source_id=r.id and branch_id=v.branch_id and status='posted';
  if v_count<>cardinality(v.finance_entry_ids) or v_amount<>v.gross_amount_idr then
    raise exception using errcode='23514',message='PAYROLL_FINANCE_POSTING_TOTAL_MISMATCH';
  end if;
  select jsonb_build_object(
    'tenant_id',p_tenant_id,'branch_id',v.branch_id,'payroll_run_id',r.id,
    'posting_id',v.id,'gross_amount_idr',v.gross_amount_idr,
    'deductions_amount_idr',v.deductions_amount_idr,'net_amount_idr',v.net_amount_idr,
    'finance_entries',coalesce(jsonb_agg(jsonb_build_object(
      'id',e.id,'entry_code',e.entry_code,'source_type',e.source_type,
      'source_id',e.source_id,'debit_account',e.debit_account,
      'credit_account',e.credit_account,'amount_idr',e.amount_idr,'status',e.status
    ) order by e.id),'[]'::jsonb)
  ) into v_evidence
  from public.finance_journal_entries e where e.id=any(v.finance_entry_ids);
  v_hash:=encode(pg_catalog.sha256(convert_to(v_evidence::text,'UTF8')),'hex');
  update public.hr_payroll_finance_postings
   set status='reconciled',reconciled_by=p_actor_user_id,reconciled_at=now(),
       reconciliation_sha256=v_hash,updated_at=now()
   where id=v.id returning * into v;
  update public.hr_payroll_runs set status='reconciled',
    reconciliation_reference=v_hash,updated_at=now() where id=r.id;
  insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
  values(p_actor_user_id,'hr.payroll.finance_reconciled','hr_payroll_finance_postings',v.id::text,
    jsonb_build_object('tenant_id',p_tenant_id,'payroll_run_id',r.id,'gross_amount_idr',v.gross_amount_idr,
      'journal_entry_count',v_count,'evidence_sha256',v_hash));
  return jsonb_build_object('status','reconciled','posting_id',v.id,'payroll_run_id',r.id,
    'gross_amount_idr',v.gross_amount_idr,'finance_entry_count',v_count,
    'reconciliation_sha256',v_hash);
end;
$$;
revoke all on function public.hr_reconcile_payroll_finance_posting(uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.hr_reconcile_payroll_finance_posting(uuid,uuid,uuid) to service_role;

do $$
declare t text;
begin
  foreach t in array array['hr_payroll_finance_account_mappings','hr_payroll_finance_postings'] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('drop policy if exists service_role_only on public.%I',t);
    execute format('create policy service_role_only on public.%I for all to service_role using(true) with check(true)',t);
    execute format('revoke all on public.%I from anon,authenticated',t);
    execute format('grant select,insert,update,delete on public.%I to service_role',t);
  end loop;
end $$;

create table if not exists public.hr_payroll_payment_provider_configs (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete restrict,
 provider_id text not null check(length(btrim(provider_id)) between 2 and 100),
 credential_secret_reference text not null check(credential_secret_reference ~ '^[A-Z][A-Z0-9_]{2,119}$'),
 status text not null default 'pending' check(status in ('pending','active','suspended','revoked')),
 created_by uuid not null references auth.users(id) on delete restrict,
 approved_by uuid null references auth.users(id) on delete restrict,
 approved_at timestamptz null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(tenant_id,id),
 unique(tenant_id,provider_id),
 check(status<>'active' or (approved_by is not null and approved_at is not null and approved_by<>created_by))
);

create table if not exists public.hr_payroll_beneficiary_profiles (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete restrict,
 branch_id uuid not null,
 employee_user_id uuid not null references auth.users(id) on delete restrict,
 beneficiary_secret_reference text not null check(beneficiary_secret_reference ~ '^[A-Z][A-Z0-9_]{2,119}$'),
 beneficiary_fingerprint_sha256 text not null check(beneficiary_fingerprint_sha256 ~ '^[0-9a-f]{64}$'),
 currency text not null default 'IDR' check(currency='IDR'),
 status text not null default 'pending' check(status in ('pending','active','suspended','revoked')),
 created_by uuid not null references auth.users(id) on delete restrict,
 approved_by uuid null references auth.users(id) on delete restrict,
 approved_at timestamptz null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(tenant_id,id),
 foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict,
 check(status<>'active' or (approved_by is not null and approved_at is not null and approved_by<>created_by))
);
create unique index if not exists hr_payroll_one_active_beneficiary_per_employee_uq
 on public.hr_payroll_beneficiary_profiles(tenant_id,branch_id,employee_user_id)
 where status='active';

create table if not exists public.hr_payroll_payment_batches (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete restrict,
 branch_id uuid not null,
 payroll_run_id uuid not null,
 finance_posting_id uuid not null,
 provider_config_id uuid not null,
 status text not null default 'draft' check(status in ('draft','approved','processing','reconciled','exception','cancelled')),
 amount_idr bigint not null check(amount_idr>0),
 item_count integer not null check(item_count>0),
 idempotency_key text not null check(length(idempotency_key) between 8 and 160),
 created_by uuid not null references auth.users(id) on delete restrict,
 approved_by uuid null references auth.users(id) on delete restrict,
 approved_at timestamptz null,
 reconciled_by uuid null references auth.users(id) on delete restrict,
 reconciled_at timestamptz null,
 reconciliation_sha256 text null check(reconciliation_sha256 is null or reconciliation_sha256 ~ '^[0-9a-f]{64}$'),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(tenant_id,id),
 unique(tenant_id,payroll_run_id),
 unique(tenant_id,idempotency_key),
 foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict,
 foreign key(tenant_id,payroll_run_id) references public.hr_payroll_runs(tenant_id,id) on delete restrict,
 foreign key(tenant_id,finance_posting_id) references public.hr_payroll_finance_postings(tenant_id,id) on delete restrict,
 foreign key(tenant_id,provider_config_id) references public.hr_payroll_payment_provider_configs(tenant_id,id) on delete restrict,
 check((status in ('approved','processing','reconciled') and approved_by is not null and approved_at is not null and approved_by<>created_by) or status not in ('approved','processing','reconciled')),
 check((status='reconciled' and reconciled_by is not null and reconciled_at is not null and reconciliation_sha256 is not null) or status<>'reconciled')
);

create table if not exists public.hr_payroll_payment_items (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete restrict,
 payment_batch_id uuid not null,
 payroll_line_id uuid not null,
 beneficiary_profile_id uuid not null,
 beneficiary_fingerprint_sha256 text not null check(beneficiary_fingerprint_sha256 ~ '^[0-9a-f]{64}$'),
 amount_idr bigint not null check(amount_idr>0),
 status text not null default 'pending' check(status in ('pending','accepted','settled','failed','reversed')),
 provider_reference text null,
 settled_at timestamptz null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(tenant_id,id),
 unique(tenant_id,payment_batch_id,payroll_line_id),
 foreign key(tenant_id,payment_batch_id) references public.hr_payroll_payment_batches(tenant_id,id) on delete restrict,
 foreign key(tenant_id,payroll_line_id) references public.hr_payroll_lines(tenant_id,id) on delete restrict,
 foreign key(tenant_id,beneficiary_profile_id) references public.hr_payroll_beneficiary_profiles(tenant_id,id) on delete restrict,
 check((status='settled' and settled_at is not null and provider_reference is not null) or status<>'settled')
);

create table if not exists public.hr_payroll_provider_events (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete restrict,
 payment_batch_id uuid not null,
 payment_item_id uuid not null,
 provider_config_id uuid not null,
 provider_event_id text not null check(length(btrim(provider_event_id)) between 1 and 180),
 event_kind text not null check(event_kind in ('accepted','settled','failed','reversed')),
 amount_idr bigint not null check(amount_idr>0),
 provider_reference text null,
 payload_sha256 text not null check(payload_sha256 ~ '^[0-9a-f]{64}$'),
 signature_verified boolean not null check(signature_verified=true),
 occurred_at timestamptz not null,
 received_at timestamptz not null default now(),
 unique(tenant_id,id),
 unique(provider_config_id,provider_event_id),
 foreign key(tenant_id,payment_batch_id) references public.hr_payroll_payment_batches(tenant_id,id) on delete restrict,
 foreign key(tenant_id,payment_item_id) references public.hr_payroll_payment_items(tenant_id,id) on delete restrict,
 foreign key(tenant_id,provider_config_id) references public.hr_payroll_payment_provider_configs(tenant_id,id) on delete restrict
);

create table if not exists public.hr_payroll_payment_reconciliations (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete restrict,
 payment_batch_id uuid not null,
 expected_amount_idr bigint not null check(expected_amount_idr>0),
 settled_amount_idr bigint not null check(settled_amount_idr>=0),
 item_count integer not null check(item_count>0),
 event_ids uuid[] not null default '{}',
 evidence_sha256 text not null check(evidence_sha256 ~ '^[0-9a-f]{64}$'),
 status text not null check(status in ('reconciled','exception')),
 reconciled_by uuid not null references auth.users(id) on delete restrict,
 reconciled_at timestamptz not null default now(),
 unique(tenant_id,id),
 unique(tenant_id,payment_batch_id),
 foreign key(tenant_id,payment_batch_id) references public.hr_payroll_payment_batches(tenant_id,id) on delete restrict,
 check(status<>'reconciled' or (expected_amount_idr=settled_amount_idr and cardinality(event_ids)>0))
);

create or replace function public.hr_approve_payroll_payment_provider(
 p_tenant_id uuid,p_provider_config_id uuid,p_actor_user_id uuid
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v public.hr_payroll_payment_provider_configs%rowtype;
begin
 select * into v from public.hr_payroll_payment_provider_configs
  where tenant_id=p_tenant_id and id=p_provider_config_id for update;
 if not found or v.status<>'pending' then raise exception using errcode='23514',message='PENDING_PAYROLL_PROVIDER_CONFIG_REQUIRED'; end if;
 if v.created_by=p_actor_user_id then raise exception using errcode='42501',message='INDEPENDENT_PAYROLL_PROVIDER_APPROVER_REQUIRED'; end if;
 update public.hr_payroll_payment_provider_configs set status='active',approved_by=p_actor_user_id,approved_at=now(),updated_at=now()
  where id=v.id returning * into v;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'hr.payroll.payment_provider_approved','hr_payroll_payment_provider_configs',v.id::text,
  jsonb_build_object('tenant_id',p_tenant_id,'provider_id',v.provider_id,'secret_reference',v.credential_secret_reference));
 return jsonb_build_object('provider_config_id',v.id,'status',v.status);
end $$;
revoke all on function public.hr_approve_payroll_payment_provider(uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.hr_approve_payroll_payment_provider(uuid,uuid,uuid) to service_role;

create or replace function public.hr_approve_payroll_beneficiary_profile(
 p_tenant_id uuid,p_profile_id uuid,p_actor_user_id uuid
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v public.hr_payroll_beneficiary_profiles%rowtype;
begin
 select * into v from public.hr_payroll_beneficiary_profiles where tenant_id=p_tenant_id and id=p_profile_id for update;
 if not found or v.status<>'pending' then raise exception using errcode='23514',message='PENDING_PAYROLL_BENEFICIARY_REQUIRED'; end if;
 if p_actor_user_id in (v.created_by,v.employee_user_id) then raise exception using errcode='42501',message='INDEPENDENT_BENEFICIARY_APPROVER_REQUIRED'; end if;
 update public.hr_payroll_beneficiary_profiles set status='active',approved_by=p_actor_user_id,approved_at=now(),updated_at=now()
  where id=v.id returning * into v;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'hr.payroll.beneficiary_approved','hr_payroll_beneficiary_profiles',v.id::text,
  jsonb_build_object('tenant_id',p_tenant_id,'branch_id',v.branch_id,'employee_user_id',v.employee_user_id,
   'beneficiary_fingerprint_sha256',v.beneficiary_fingerprint_sha256));
 return jsonb_build_object('profile_id',v.id,'status',v.status);
end $$;
revoke all on function public.hr_approve_payroll_beneficiary_profile(uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.hr_approve_payroll_beneficiary_profile(uuid,uuid,uuid) to service_role;

-- Build the payment batch exclusively from persisted payroll lines and active,
-- independently approved beneficiary profiles. No amounts or account numbers
-- are accepted from the caller.
create or replace function public.hr_prepare_payroll_payment_batch(
 p_tenant_id uuid,p_branch_id uuid,p_payroll_run_id uuid,p_provider_config_id uuid,
 p_idempotency_key text,p_actor_user_id uuid
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare
 v_run public.hr_payroll_runs%rowtype;
 v_post public.hr_payroll_finance_postings%rowtype;
 v_provider public.hr_payroll_payment_provider_configs%rowtype;
 v_batch public.hr_payroll_payment_batches%rowtype;
 v_count integer; v_amount bigint;
begin
 if length(coalesce(p_idempotency_key,'')) not between 8 and 160 then
  raise exception using errcode='22023',message='INVALID_PAYROLL_PAYMENT_IDEMPOTENCY_KEY';
 end if;
 select * into v_run from public.hr_payroll_runs
  where tenant_id=p_tenant_id and branch_id=p_branch_id and id=p_payroll_run_id for update;
 if not found or v_run.status<>'reconciled' or v_run.finance_journal_id is null then
  raise exception using errcode='23514',message='RECONCILED_PAYROLL_RUN_REQUIRED';
 end if;
 select * into v_post from public.hr_payroll_finance_postings
  where tenant_id=p_tenant_id and id=v_run.finance_journal_id and payroll_run_id=v_run.id
   and status='reconciled' for share;
 if not found or v_post.gross_amount_idr<>v_run.gross_amount_idr
   or v_post.deductions_amount_idr<>v_run.deductions_amount_idr
   or v_post.net_amount_idr<>v_run.net_amount_idr then
  raise exception using errcode='23514',message='RECONCILED_FINANCE_POSTING_REQUIRED';
 end if;
 select * into v_provider from public.hr_payroll_payment_provider_configs
  where tenant_id=p_tenant_id and id=p_provider_config_id and status='active' for share;
 if not found then raise exception using errcode='23514',message='APPROVED_PAYROLL_PAYMENT_PROVIDER_REQUIRED'; end if;
 select count(*) filter(where net_amount_idr>0),coalesce(sum(net_amount_idr),0) into v_count,v_amount
  from public.hr_payroll_lines where tenant_id=p_tenant_id and payroll_run_id=p_payroll_run_id and branch_id=p_branch_id;
 if exists(select 1 from public.hr_payroll_lines where tenant_id=p_tenant_id and payroll_run_id=p_payroll_run_id and branch_id<>p_branch_id) then
  raise exception using errcode='23514',message='PAYROLL_LINE_BRANCH_SCOPE_MISMATCH';
 end if;
 if v_count=0 or v_amount<>v_run.net_amount_idr then
  raise exception using errcode='23514',message='PAYROLL_PAYMENT_LINES_DO_NOT_RECONCILE';
 end if;
 if exists(
  select 1 from public.hr_payroll_lines l
  where l.tenant_id=p_tenant_id and l.payroll_run_id=p_payroll_run_id
   and l.net_amount_idr>0
   and not exists(select 1 from public.hr_payroll_beneficiary_profiles b
    where b.tenant_id=l.tenant_id and b.branch_id=l.branch_id and b.employee_user_id=l.employee_user_id
     and b.status='active' and b.approved_by is not null and b.approved_at is not null)
 ) then raise exception using errcode='23514',message='APPROVED_BENEFICIARY_PROFILE_REQUIRED_FOR_EVERY_PAYROLL_LINE'; end if;
 select * into v_batch from public.hr_payroll_payment_batches
  where tenant_id=p_tenant_id and payroll_run_id=p_payroll_run_id for update;
 if found then
  if v_batch.idempotency_key<>p_idempotency_key or v_batch.provider_config_id<>p_provider_config_id
   or v_batch.amount_idr<>v_amount then
   raise exception using errcode='23505',message='PAYROLL_PAYMENT_BATCH_IDEMPOTENCY_COLLISION';
  end if;
  return jsonb_build_object('status',v_batch.status,'payment_batch_id',v_batch.id,'amount_idr',v_batch.amount_idr);
 end if;
 insert into public.hr_payroll_payment_batches(
  tenant_id,branch_id,payroll_run_id,finance_posting_id,provider_config_id,status,
  amount_idr,item_count,idempotency_key,created_by
 ) values(p_tenant_id,p_branch_id,p_payroll_run_id,v_post.id,v_provider.id,'draft',
  v_amount,v_count,p_idempotency_key,p_actor_user_id) returning * into v_batch;
 insert into public.hr_payroll_payment_items(
  tenant_id,payment_batch_id,payroll_line_id,beneficiary_profile_id,
  beneficiary_fingerprint_sha256,amount_idr
 )
 select p_tenant_id,v_batch.id,l.id,b.id,b.beneficiary_fingerprint_sha256,l.net_amount_idr
 from public.hr_payroll_lines l
 join public.hr_payroll_beneficiary_profiles b
  on b.tenant_id=l.tenant_id and b.branch_id=l.branch_id and b.employee_user_id=l.employee_user_id and b.status='active'
 where l.tenant_id=p_tenant_id and l.payroll_run_id=p_payroll_run_id and l.net_amount_idr>0
 order by l.employee_user_id,l.id;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'hr.payroll.payment_batch_prepared','hr_payroll_payment_batches',v_batch.id::text,
  jsonb_build_object('tenant_id',p_tenant_id,'payroll_run_id',p_payroll_run_id,'finance_posting_id',v_post.id,
   'provider_id',v_provider.provider_id,'amount_idr',v_amount,'item_count',v_count));
 return jsonb_build_object('status','draft','payment_batch_id',v_batch.id,'amount_idr',v_amount,'item_count',v_count);
end $$;
revoke all on function public.hr_prepare_payroll_payment_batch(uuid,uuid,uuid,uuid,text,uuid) from public,anon,authenticated;
grant execute on function public.hr_prepare_payroll_payment_batch(uuid,uuid,uuid,uuid,text,uuid) to service_role;

create or replace function public.hr_approve_payroll_payment_batch(
 p_tenant_id uuid,p_payment_batch_id uuid,p_actor_user_id uuid
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v public.hr_payroll_payment_batches%rowtype; r public.hr_payroll_runs%rowtype; f public.hr_payroll_finance_postings%rowtype;
begin
 select * into v from public.hr_payroll_payment_batches where tenant_id=p_tenant_id and id=p_payment_batch_id for update;
 if not found or v.status<>'draft' then raise exception using errcode='23514',message='PAYROLL_PAYMENT_DRAFT_REQUIRED'; end if;
 select * into r from public.hr_payroll_runs where tenant_id=p_tenant_id and id=v.payroll_run_id for share;
 select * into f from public.hr_payroll_finance_postings where tenant_id=p_tenant_id and id=v.finance_posting_id for share;
 if p_actor_user_id in (v.created_by,r.created_by,r.generated_by,r.submitted_by,r.approved_by,f.created_by,f.posted_by,f.reconciled_by) then
  raise exception using errcode='42501',message='INDEPENDENT_PAYROLL_PAYMENT_APPROVER_REQUIRED';
 end if;
 if exists(select 1 from public.hr_payroll_payment_items i
  join public.hr_payroll_beneficiary_profiles b on b.tenant_id=i.tenant_id and b.id=i.beneficiary_profile_id
  where i.tenant_id=p_tenant_id and i.payment_batch_id=v.id
   and p_actor_user_id in (b.created_by,b.approved_by,b.employee_user_id)) then
  raise exception using errcode='42501',message='PAYMENT_APPROVER_MUST_BE_INDEPENDENT_OF_BENEFICIARY_MAINTENANCE';
 end if;
 update public.hr_payroll_payment_batches set status='approved',approved_by=p_actor_user_id,approved_at=now(),updated_at=now()
  where id=v.id returning * into v;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'hr.payroll.payment_batch_approved','hr_payroll_payment_batches',v.id::text,
  jsonb_build_object('tenant_id',p_tenant_id,'amount_idr',v.amount_idr,'item_count',v.item_count));
 return jsonb_build_object('payment_batch_id',v.id,'status',v.status,'amount_idr',v.amount_idr);
end $$;
revoke all on function public.hr_approve_payroll_payment_batch(uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.hr_approve_payroll_payment_batch(uuid,uuid,uuid) to service_role;

-- Invoke only after the provider-specific Edge adapter verifies the raw-body
-- signature. This RPC is service-role-only; a caller cannot self-assert trust
-- through the public API.
create or replace function public.hr_apply_payroll_provider_event(
 p_tenant_id uuid,p_payment_batch_id uuid,p_payment_item_id uuid,
 p_provider_event_id text,p_event_kind text,p_amount_idr bigint,
 p_provider_reference text,p_payload_sha256 text,p_occurred_at timestamptz,
 p_signature_verified boolean,p_actor_user_id uuid
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare
 v_batch public.hr_payroll_payment_batches%rowtype;
 v_item public.hr_payroll_payment_items%rowtype;
 v_event public.hr_payroll_provider_events%rowtype;
begin
 if p_signature_verified is distinct from true or coalesce(p_payload_sha256,'') !~ '^[0-9a-f]{64}$'
  or length(btrim(coalesce(p_provider_event_id,''))) not between 1 and 180
  or p_event_kind not in ('accepted','settled','failed','reversed') then
  raise exception using errcode='42501',message='VERIFIED_PROVIDER_EVENT_REQUIRED';
 end if;
 select * into v_batch from public.hr_payroll_payment_batches
  where tenant_id=p_tenant_id and id=p_payment_batch_id for update;
 if not found or v_batch.status not in ('approved','processing') then
  raise exception using errcode='23514',message='APPROVED_PAYROLL_PAYMENT_BATCH_REQUIRED';
 end if;
 select * into v_item from public.hr_payroll_payment_items
  where tenant_id=p_tenant_id and payment_batch_id=v_batch.id and id=p_payment_item_id for update;
 if not found or p_amount_idr<>v_item.amount_idr then
  raise exception using errcode='23514',message='PAYROLL_PROVIDER_EVENT_ITEM_AMOUNT_MISMATCH';
 end if;
 if not exists(select 1 from public.hr_payroll_payment_provider_configs c
  where c.tenant_id=p_tenant_id and c.id=v_batch.provider_config_id and c.status='active') then
  raise exception using errcode='23514',message='PAYROLL_PROVIDER_CONFIG_NOT_ACTIVE';
 end if;
 select * into v_event from public.hr_payroll_provider_events
  where provider_config_id=v_batch.provider_config_id and provider_event_id=p_provider_event_id for update;
 if found then
  if v_event.payment_item_id<>v_item.id or v_event.payload_sha256<>p_payload_sha256 then
   raise exception using errcode='23505',message='PAYROLL_PROVIDER_EVENT_IDEMPOTENCY_COLLISION';
  end if;
  return jsonb_build_object('status','duplicate','event_id',v_event.id,'payment_item_status',v_item.status);
 end if;
 if p_event_kind='settled' and (v_item.status in ('failed','reversed') or p_provider_reference is null) then
  raise exception using errcode='23514',message='PAYROLL_PAYMENT_ITEM_NOT_SETTLEABLE';
 end if;
 insert into public.hr_payroll_provider_events(
  tenant_id,payment_batch_id,payment_item_id,provider_config_id,provider_event_id,
  event_kind,amount_idr,provider_reference,payload_sha256,signature_verified,occurred_at
 ) values(p_tenant_id,v_batch.id,v_item.id,v_batch.provider_config_id,p_provider_event_id,
  p_event_kind,p_amount_idr,p_provider_reference,p_payload_sha256,true,p_occurred_at)
 returning * into v_event;
 update public.hr_payroll_payment_items set
  status=case p_event_kind when 'accepted' then 'accepted' when 'settled' then 'settled'
    when 'failed' then 'failed' when 'reversed' then 'reversed' end,
  provider_reference=coalesce(p_provider_reference,provider_reference),
  settled_at=case when p_event_kind='settled' then p_occurred_at else settled_at end,
  updated_at=now() where id=v_item.id returning * into v_item;
 update public.hr_payroll_payment_batches set status='processing',updated_at=now() where id=v_batch.id;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'hr.payroll.provider_event_applied','hr_payroll_provider_events',v_event.id::text,
  jsonb_build_object('tenant_id',p_tenant_id,'payment_batch_id',v_batch.id,'payment_item_id',v_item.id,
   'event_kind',p_event_kind,'amount_idr',p_amount_idr,'payload_sha256',p_payload_sha256));
 return jsonb_build_object('status','applied','event_id',v_event.id,'payment_item_status',v_item.status);
end $$;
revoke all on function public.hr_apply_payroll_provider_event(uuid,uuid,uuid,text,text,bigint,text,text,timestamptz,boolean,uuid) from public,anon,authenticated;
grant execute on function public.hr_apply_payroll_provider_event(uuid,uuid,uuid,text,text,bigint,text,text,timestamptz,boolean,uuid) to service_role;

create or replace function public.hr_reconcile_payroll_payment_batch(
 p_tenant_id uuid,p_payment_batch_id uuid,p_actor_user_id uuid
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare
 v public.hr_payroll_payment_batches%rowtype;
 r public.hr_payroll_runs%rowtype;
 v_count integer; v_settled bigint; v_event_ids uuid[]; v_event_item_count integer; v_event_amount bigint; v_evidence jsonb; v_hash text; f public.hr_payroll_finance_postings%rowtype;
begin
 select * into v from public.hr_payroll_payment_batches where tenant_id=p_tenant_id and id=p_payment_batch_id for update;
 if not found or v.status<>'processing' then raise exception using errcode='23514',message='PROCESSING_PAYROLL_PAYMENT_BATCH_REQUIRED'; end if;
 select * into r from public.hr_payroll_runs where tenant_id=p_tenant_id and id=v.payroll_run_id for share;
 select * into f from public.hr_payroll_finance_postings where tenant_id=p_tenant_id and id=v.finance_posting_id for share;
 if p_actor_user_id in (v.created_by,v.approved_by,r.created_by,r.generated_by,r.submitted_by,r.approved_by,f.created_by,f.posted_by,f.reconciled_by) then
  raise exception using errcode='42501',message='INDEPENDENT_PAYROLL_PAYMENT_RECONCILER_REQUIRED';
 end if;
 if exists(select 1 from public.hr_payroll_payment_items where tenant_id=p_tenant_id and payment_batch_id=v.id and status<>'settled') then
  raise exception using errcode='23514',message='ALL_PAYROLL_PAYMENT_ITEMS_MUST_BE_SETTLED';
 end if;
 select count(*),coalesce(sum(amount_idr),0) into v_count,v_settled
  from public.hr_payroll_payment_items where tenant_id=p_tenant_id and payment_batch_id=v.id and status='settled';
 if v_count<>v.item_count or v_settled<>v.amount_idr then
  raise exception using errcode='23514',message='PAYROLL_PAYMENT_SETTLEMENT_TOTAL_MISMATCH';
 end if;
 select coalesce(array_agg(e.id order by e.id),'{}'::uuid[]),
        count(distinct e.payment_item_id),coalesce(sum(e.amount_idr),0)
  into v_event_ids,v_event_item_count,v_event_amount
  from public.hr_payroll_provider_events e
  join public.hr_payroll_payment_items i on i.tenant_id=e.tenant_id and i.id=e.payment_item_id
  where e.tenant_id=p_tenant_id and e.payment_batch_id=v.id and e.event_kind='settled'
   and i.status='settled';
 if cardinality(v_event_ids)=0 or v_event_item_count<>v.item_count or v_event_amount<>v.amount_idr then
  raise exception using errcode='23514',message='SETTLED_PROVIDER_EVENT_MISSING_FOR_PAYMENT_ITEM';
 end if;
 select jsonb_build_object('tenant_id',p_tenant_id,'payment_batch_id',v.id,
  'payroll_run_id',v.payroll_run_id,'finance_posting_id',v.finance_posting_id,
  'provider_config_id',v.provider_config_id,'amount_idr',v.amount_idr,
  'items',coalesce((select jsonb_agg(jsonb_build_object('item_id',i.id,'payroll_line_id',i.payroll_line_id,
    'beneficiary_fingerprint_sha256',i.beneficiary_fingerprint_sha256,'amount_idr',i.amount_idr,
    'provider_reference',i.provider_reference,'settled_at',i.settled_at) order by i.id)
   from public.hr_payroll_payment_items i where i.tenant_id=p_tenant_id and i.payment_batch_id=v.id),'[]'::jsonb),
  'events',coalesce((select jsonb_agg(jsonb_build_object('event_id',e.id,'provider_event_id',e.provider_event_id,
    'event_kind',e.event_kind,'amount_idr',e.amount_idr,'payload_sha256',e.payload_sha256,
    'occurred_at',e.occurred_at) order by e.id)
   from public.hr_payroll_provider_events e where e.tenant_id=p_tenant_id and e.payment_batch_id=v.id),'[]'::jsonb)
 ) into v_evidence;
 v_hash:=encode(pg_catalog.sha256(convert_to(v_evidence::text,'UTF8')),'hex');
 insert into public.hr_payroll_payment_reconciliations(
  tenant_id,payment_batch_id,expected_amount_idr,settled_amount_idr,item_count,event_ids,
  evidence_sha256,status,reconciled_by
 ) values(p_tenant_id,v.id,v.amount_idr,v_settled,v_count,v_event_ids,v_hash,'reconciled',p_actor_user_id);
 update public.hr_payroll_payment_batches set status='reconciled',reconciled_by=p_actor_user_id,
  reconciled_at=now(),reconciliation_sha256=v_hash,updated_at=now() where id=v.id returning * into v;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'hr.payroll.payment_batch_reconciled','hr_payroll_payment_batches',v.id::text,
  jsonb_build_object('tenant_id',p_tenant_id,'payroll_run_id',v.payroll_run_id,'amount_idr',v.amount_idr,
   'item_count',v_count,'evidence_sha256',v_hash));
 return jsonb_build_object('status','reconciled','payment_batch_id',v.id,'amount_idr',v.amount_idr,
  'item_count',v_count,'evidence_sha256',v_hash);
end $$;
revoke all on function public.hr_reconcile_payroll_payment_batch(uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.hr_reconcile_payroll_payment_batch(uuid,uuid,uuid) to service_role;

create or replace function public.hr_reject_payroll_provider_event_mutation()
returns trigger language plpgsql security invoker set search_path=''
as $$
begin
 raise exception using errcode='55000',message='PAYROLL_PROVIDER_EVENTS_APPEND_ONLY';
end $$;
revoke all on function public.hr_reject_payroll_provider_event_mutation() from public,anon,authenticated;
drop trigger if exists hr_payroll_provider_events_append_only on public.hr_payroll_provider_events;
create trigger hr_payroll_provider_events_append_only before update or delete on public.hr_payroll_provider_events
for each row execute function public.hr_reject_payroll_provider_event_mutation();

do $$
declare t text;
begin
 foreach t in array array[
  'hr_payroll_payment_provider_configs','hr_payroll_beneficiary_profiles',
  'hr_payroll_payment_batches','hr_payroll_payment_items',
  'hr_payroll_provider_events','hr_payroll_payment_reconciliations'
 ] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('drop policy if exists service_role_only on public.%I',t);
  execute format('create policy service_role_only on public.%I for all to service_role using(true) with check(true)',t);
  execute format('revoke all on public.%I from anon,authenticated',t);
  execute format('grant select,insert,update,delete on public.%I to service_role',t);
 end loop;
end $$;

-- External provider dispatch and raw-body signature verification remain disabled
-- until an exact provider contract and staging credentials are approved.

-- Trigger functions are non-client-callable; service_role retains internal EXECUTE for the global ACL contract.
grant execute on function public.hr_audit_row_change() to service_role;
grant execute on function public.hr_reject_employee_lifecycle_event_mutation() to service_role;
grant execute on function public.hr_reject_payroll_provider_event_mutation() to service_role;
