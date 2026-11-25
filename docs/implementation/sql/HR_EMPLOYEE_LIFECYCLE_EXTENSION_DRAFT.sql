-- DESIGN DRAFT ONLY — apply after HR_WORKFORCE_SCHEMA_DRAFT.sql.
-- Existing Auth identities, admin_profiles, tenant_memberships and branch_assignments
-- remain canonical. This extension records HR lifecycle and synchronizes only the
-- employee's assignment/membership inside the selected tenant in one DB transaction.
-- It never creates/deletes Auth users or changes global admin_profiles.is_active.

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
    if exists(select 1 from public.branch_assignments ba join public.branches b on b.id=ba.branch_id
      where b.tenant_id=p_tenant_id and ba.user_id=p_employee_user_id
        and ba.employment_status='active' and p_effective_on<=ba.starts_on) then
      raise exception using errcode='23514',message='HR_TRANSFER_EFFECTIVE_DATE_INVALID';
    end if;
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
