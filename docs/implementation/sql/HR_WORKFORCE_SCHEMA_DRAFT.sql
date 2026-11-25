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
as $
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
$;
revoke all on function public.hr_record_attendance(uuid,uuid,uuid,text,text,text,text,uuid) from public,anon,authenticated;
grant execute on function public.hr_record_attendance(uuid,uuid,uuid,text,text,text,text,uuid) to service_role;

create or replace function public.hr_create_leave_request(
 p_tenant_id uuid,p_branch_id uuid,p_employee_user_id uuid,p_leave_type text,
 p_starts_on date,p_ends_on date,p_coverage_employee_user_id uuid,p_reason text,p_actor_user_id uuid
) returns jsonb language plpgsql security invoker set search_path=''
as $
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
end $;
revoke all on function public.hr_create_leave_request(uuid,uuid,uuid,text,date,date,uuid,text,uuid) from public,anon,authenticated;
grant execute on function public.hr_create_leave_request(uuid,uuid,uuid,text,date,date,uuid,text,uuid) to service_role;

create or replace function public.hr_confirm_leave_coverage(p_leave_request_id uuid,p_actor_user_id uuid,p_approved boolean,p_note text)
returns jsonb language plpgsql security invoker set search_path=''
as $
declare v public.hr_leave_requests%rowtype;
begin
 select * into v from public.hr_leave_requests where id=p_leave_request_id for update;
 if not found then raise exception using errcode='P0002',message='LEAVE_REQUEST_NOT_FOUND'; end if;
 if v.status<>'submitted' or v.coverage_employee_user_id is null then raise exception using errcode='23514',message='LEAVE_COVERAGE_NOT_REQUIRED_OR_CLOSED'; end if;
 if v.coverage_employee_user_id<>p_actor_user_id then raise exception using errcode='42501',message='ONLY_COVERAGE_EMPLOYEE_CAN_CONFIRM'; end if;
 update public.hr_leave_requests set coverage_approved=p_approved,review_note=left(coalesce(p_note,''),500),updated_at=now() where id=v.id;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,case when p_approved then 'hr.leave.coverage_accepted' else 'hr.leave.coverage_rejected' end,
 'hr_leave_request',v.id::text,jsonb_build_object('tenant_id',v.tenant_id,'employee_user_id',v.employee_user_id));
 return jsonb_build_object('leave_request_id',v.id,'coverage_approved',p_approved);
end $;
revoke all on function public.hr_confirm_leave_coverage(uuid,uuid,boolean,text) from public,anon,authenticated;
grant execute on function public.hr_confirm_leave_coverage(uuid,uuid,boolean,text) to service_role;

create or replace function public.hr_review_leave_request(p_leave_request_id uuid,p_actor_user_id uuid,p_approve boolean,p_note text)
returns jsonb language plpgsql security invoker set search_path=''
as $
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
end $;
revoke all on function public.hr_review_leave_request(uuid,uuid,boolean,text) from public,anon,authenticated;
grant execute on function public.hr_review_leave_request(uuid,uuid,boolean,text) to service_role;

create or replace function public.hr_create_shift_schedule(
 p_tenant_id uuid,p_branch_id uuid,p_employee_user_id uuid,p_job_position_id uuid,
 p_starts_at timestamptz,p_ends_at timestamptz,p_created_by uuid,p_notes text
) returns jsonb language plpgsql security invoker set search_path=''
as $
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
end $;
revoke all on function public.hr_create_shift_schedule(uuid,uuid,uuid,uuid,timestamptz,timestamptz,uuid,text) from public,anon,authenticated;
grant execute on function public.hr_create_shift_schedule(uuid,uuid,uuid,uuid,timestamptz,timestamptz,uuid,text) to service_role;

create or replace function public.hr_generate_timesheet(
 p_tenant_id uuid,p_branch_id uuid,p_employee_user_id uuid,p_period_start date,p_period_end date,p_created_by uuid
) returns jsonb language plpgsql security invoker set search_path=''
as $
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
end $;
revoke all on function public.hr_generate_timesheet(uuid,uuid,uuid,date,date,uuid) from public,anon,authenticated;
grant execute on function public.hr_generate_timesheet(uuid,uuid,uuid,date,date,uuid) to service_role;

create or replace function public.hr_submit_timesheet(p_timesheet_id uuid,p_actor_user_id uuid)
returns jsonb language plpgsql security invoker set search_path=''
as $
declare v public.hr_timesheets%rowtype;
begin
 select * into v from public.hr_timesheets where id=p_timesheet_id for update;
 if not found then raise exception using errcode='P0002',message='TIMESHEET_NOT_FOUND'; end if;
 if v.employee_user_id<>p_actor_user_id then raise exception using errcode='42501',message='ONLY_EMPLOYEE_CAN_SUBMIT_TIMESHEET'; end if;
 if v.status<>'draft' or cardinality(v.attendance_event_ids)=0 then raise exception using errcode='23514',message='TIMESHEET_NOT_SUBMITTABLE'; end if;
 update public.hr_timesheets set status='submitted',submitted_at=now(),updated_at=now() where id=v.id;
 return jsonb_build_object('timesheet_id',v.id,'status','submitted');
end $;
revoke all on function public.hr_submit_timesheet(uuid,uuid) from public,anon,authenticated;
grant execute on function public.hr_submit_timesheet(uuid,uuid) to service_role;

create or replace function public.hr_approve_timesheet(p_timesheet_id uuid,p_actor_user_id uuid)
returns jsonb language plpgsql security invoker set search_path=''
as $
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
end $;
revoke all on function public.hr_approve_timesheet(uuid,uuid) from public,anon,authenticated;
grant execute on function public.hr_approve_timesheet(uuid,uuid) to service_role;

-- Important: attendance and leave endpoints must verify an active tenant membership
-- AND an active branch_assignment for the employee before accepting a record.
-- Payroll posting must later write a balanced finance_journal_entries source reference
-- and reconcile approved timesheets before status may move to posted.
