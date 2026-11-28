-- Branch Operations canonical persistence draft.
-- Generate the official migration with `supabase migration new branch_operations_persistence`
-- after review. This draft is not applied to staging or production.
create table if not exists public.branch_ops_equipment (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  branch_id uuid not null,
  asset_code text not null check (length(btrim(asset_code)) between 1 and 80),
  name text not null check (length(btrim(name)) between 1 and 160),
  status text not null default 'active' check (status in ('active','maintenance','retired')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id,id),
  unique (tenant_id,branch_id,asset_code),
  foreign key (tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict
);

create table if not exists public.branch_ops_tasks (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  branch_id uuid not null,
  title text not null check (length(btrim(title)) between 1 and 200),
  description text null check (description is null or length(description)<=4000),
  due_at timestamptz not null,
  assignee_user_id uuid not null references auth.users(id) on delete restrict,
  priority text not null default 'normal' check (priority in ('low','normal','high','critical')),
  status text not null default 'open' check (status in ('open','in_progress','completed','cancelled')),
  source_type text not null default 'manual',
  source_id uuid null,
  idempotency_key text not null check (length(idempotency_key) between 8 and 120),
  created_by uuid not null references auth.users(id) on delete restrict,
  completed_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id,id),
  unique (tenant_id,idempotency_key),
  foreign key (tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict
);
create index if not exists branch_ops_tasks_branch_status_due_idx
  on public.branch_ops_tasks(tenant_id,branch_id,status,due_at);
create index if not exists branch_ops_tasks_assignee_due_idx
  on public.branch_ops_tasks(tenant_id,assignee_user_id,due_at);

create table if not exists public.branch_ops_evidence_assets (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  branch_id uuid not null,
  bucket_id text not null default 'branch-ops-evidence' check (bucket_id='branch-ops-evidence'),
  object_path text not null unique,
  owner_user_id uuid not null references auth.users(id) on delete restrict,
  purpose text not null check (purpose in ('branch_incident','branch_compliance','branch_maintenance')),
  mime_type text not null check (mime_type in ('image/jpeg','image/png','application/pdf')),
  size_bytes bigint not null check (size_bytes between 1 and 8388608),
  retention_until timestamptz not null,
  created_at timestamptz not null default now(),
  unique (tenant_id,id),
  foreign key (tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict
);
create index if not exists branch_ops_evidence_scope_retention_idx
  on public.branch_ops_evidence_assets(tenant_id,branch_id,purpose,retention_until);

create table if not exists public.branch_ops_incidents (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  branch_id uuid not null,
  category text not null check (length(btrim(category)) between 1 and 80),
  description text not null check (length(btrim(description)) between 1 and 4000),
  severity text not null check (severity in ('low','medium','high','critical')),
  status text not null default 'open' check (status in ('open','investigating','resolved','closed')),
  occurred_at timestamptz null,
  evidence_asset_ids uuid[] not null default '{}',
  escalation_task_id uuid null,
  idempotency_key text not null check (length(idempotency_key) between 8 and 120),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id,id),
  unique (tenant_id,idempotency_key),
  foreign key (tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict,
  foreign key (tenant_id,escalation_task_id) references public.branch_ops_tasks(tenant_id,id) on delete restrict
);
create index if not exists branch_ops_incidents_branch_status_idx
  on public.branch_ops_incidents(tenant_id,branch_id,status,created_at desc);

create table if not exists public.branch_ops_work_orders (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  branch_id uuid not null,
  equipment_id uuid not null,
  maintenance_type text not null check (maintenance_type in ('preventive','corrective','inspection')),
  status text not null default 'scheduled' check (status in ('scheduled','in_progress','completed','cancelled')),
  scheduled_at timestamptz not null,
  description text not null check (length(btrim(description)) between 1 and 4000),
  assigned_to uuid null references auth.users(id) on delete restrict,
  evidence_asset_ids uuid[] not null default '{}',
  idempotency_key text not null check (length(idempotency_key) between 8 and 120),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id,id),
  unique (tenant_id,idempotency_key),
  foreign key (tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict,
  foreign key (tenant_id,equipment_id) references public.branch_ops_equipment(tenant_id,id) on delete restrict
);
create index if not exists branch_ops_work_orders_branch_status_idx
  on public.branch_ops_work_orders(tenant_id,branch_id,status,scheduled_at);

create table if not exists public.branch_ops_compliance_checks (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  branch_id uuid not null,
  check_key text not null check (length(btrim(check_key)) between 1 and 100),
  title text not null check (length(btrim(title)) between 1 and 200),
  weight integer not null default 1 check (weight between 1 and 100),
  result text not null default 'pending' check (result in ('pending','pass','fail','not_applicable')),
  status text not null default 'draft' check (status in ('draft','submitted','approved','rejected')),
  evidence_asset_id uuid null,
  business_date date not null,
  created_by uuid not null references auth.users(id) on delete restrict,
  approved_by uuid null references auth.users(id) on delete restrict,
  approved_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id,id),
  unique (tenant_id,branch_id,check_key,business_date),
  foreign key (tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict,
  foreign key (tenant_id,evidence_asset_id) references public.branch_ops_evidence_assets(tenant_id,id) on delete restrict,
  check (status<>'approved' or (approved_by is not null and approved_at is not null and result in ('pass','fail','not_applicable')))
);
create index if not exists branch_ops_compliance_checks_period_idx
  on public.branch_ops_compliance_checks(tenant_id,branch_id,business_date,status);

create table if not exists public.branch_ops_compliance_snapshots (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  branch_id uuid not null,
  period_start date not null,
  period_end date not null,
  score numeric(5,2) not null check (score between 0 and 100),
  completed_checks integer not null check (completed_checks > 0),
  required_checks integer not null check (required_checks > 0 and completed_checks=required_checks),
  evidence_asset_ids uuid[] not null,
  source_revision text not null,
  idempotency_key text not null check (length(idempotency_key) between 8 and 120),
  published_by uuid not null references auth.users(id) on delete restrict,
  published_at timestamptz not null default now(),
  unique (tenant_id,id),
  unique (tenant_id,branch_id,period_start,period_end),
  unique (tenant_id,idempotency_key),
  foreign key (tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict,
  check (period_end>=period_start)
);

-- Tables are server-written only. No browser role receives table privileges.
alter table public.branch_ops_equipment enable row level security;
alter table public.branch_ops_tasks enable row level security;
alter table public.branch_ops_evidence_assets enable row level security;
alter table public.branch_ops_incidents enable row level security;
alter table public.branch_ops_work_orders enable row level security;
alter table public.branch_ops_compliance_checks enable row level security;
alter table public.branch_ops_compliance_snapshots enable row level security;
revoke all on public.branch_ops_equipment,public.branch_ops_tasks,public.branch_ops_evidence_assets,
  public.branch_ops_incidents,public.branch_ops_work_orders,public.branch_ops_compliance_checks,
  public.branch_ops_compliance_snapshots from anon,authenticated;
grant select,insert,update,delete on public.branch_ops_equipment,public.branch_ops_tasks,
  public.branch_ops_evidence_assets,public.branch_ops_incidents,public.branch_ops_work_orders,
  public.branch_ops_compliance_checks,public.branch_ops_compliance_snapshots to service_role;
create policy branch_ops_equipment_service_only on public.branch_ops_equipment for all to service_role using (true) with check (true);
create policy branch_ops_tasks_service_only on public.branch_ops_tasks for all to service_role using (true) with check (true);
create policy branch_ops_evidence_service_only on public.branch_ops_evidence_assets for all to service_role using (true) with check (true);
create policy branch_ops_incidents_service_only on public.branch_ops_incidents for all to service_role using (true) with check (true);
create policy branch_ops_work_orders_service_only on public.branch_ops_work_orders for all to service_role using (true) with check (true);
create policy branch_ops_compliance_checks_service_only on public.branch_ops_compliance_checks for all to service_role using (true) with check (true);
create policy branch_ops_compliance_snapshots_service_only on public.branch_ops_compliance_snapshots for all to service_role using (true) with check (true);

-- Private evidence bucket; authenticated uploads are restricted to the caller's own
-- tenant/branch path and active branch assignment. Downloads remain private.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('branch-ops-evidence','branch-ops-evidence',false,8388608,array['image/jpeg','image/png','application/pdf'])
on conflict (id) do update set public=false,file_size_limit=8388608,allowed_mime_types=excluded.allowed_mime_types;

-- No anon/authenticated Storage policies are created. All uploads and downloads
-- go through the authenticated server function using service_role; the bucket
-- remains private and direct client Storage access is denied by default.

-- RPCs are intentionally service_role-only. The Edge Function must authenticate
-- the bearer token, resolve tenant membership and branch assignment, then call
-- these server-side operations with the verified actor id.
create or replace function public.branch_ops_prevent_immutable_record_mutation()
returns trigger language plpgsql security invoker set search_path=public,pg_temp as $
begin
  raise exception 'BRANCH_OPS_RECORD_IMMUTABLE' using errcode='55000';
end $;
create trigger branch_ops_evidence_assets_immutable
before update or delete on public.branch_ops_evidence_assets
for each row execute function public.branch_ops_prevent_immutable_record_mutation();
create trigger branch_ops_compliance_snapshots_immutable
before update or delete on public.branch_ops_compliance_snapshots
for each row execute function public.branch_ops_prevent_immutable_record_mutation();

create or replace function public.branch_ops_assert_actor(p_tenant_id uuid,p_branch_id uuid,p_actor_id uuid)
returns void language plpgsql security invoker set search_path=public,pg_temp as $$
declare v_allowed boolean;
begin
  select exists (
    select 1 from public.branches b
    join public.tenant_memberships tm on tm.tenant_id=b.tenant_id
    where b.id=p_branch_id and b.tenant_id=p_tenant_id
      and tm.user_id=p_actor_id and tm.status='active'
      and (
        tm.role in ('tenant_owner','tenant_admin')
        or exists (select 1 from public.branch_assignments ba where ba.branch_id=b.id
          and ba.user_id=p_actor_id and ba.employment_status='active'
          and (ba.ends_on is null or ba.ends_on>=current_date))
      )
  ) into v_allowed;
  if not v_allowed then raise exception 'BRANCH_OPS_FORBIDDEN' using errcode='42501'; end if;
end $$;


create or replace function public.branch_ops_assert_approver(p_tenant_id uuid,p_branch_id uuid,p_actor_id uuid)
returns void language plpgsql security invoker set search_path=public,pg_temp as $$
declare v_allowed boolean;
begin
 perform public.branch_ops_assert_actor(p_tenant_id,p_branch_id,p_actor_id);
 select exists(select 1 from public.tenant_memberships tm
   where tm.tenant_id=p_tenant_id and tm.user_id=p_actor_id and tm.status='active'
   and (
     tm.role in ('tenant_owner','tenant_admin','branch_manager','manager')
     or tm.permissions @> '["branch_operations_approve"]'::jsonb
     or tm.permissions @> '["*"]'::jsonb
   )) into v_allowed;
 if not v_allowed then raise exception 'BRANCH_OPS_APPROVAL_FORBIDDEN' using errcode='42501'; end if;
end $$;

create or replace function public.branch_ops_create_task(
 p_tenant_id uuid,p_branch_id uuid,p_actor_id uuid,p_assignee_id uuid,p_idempotency_key text,
 p_title text,p_description text,p_due_at timestamptz,p_priority text,p_source_type text,p_source_id uuid
) returns jsonb language plpgsql security invoker set search_path=public,pg_temp as $$
declare v_row public.branch_ops_tasks;
begin
 perform public.branch_ops_assert_actor(p_tenant_id,p_branch_id,p_actor_id);
 if not exists(select 1 from public.branch_assignments ba where ba.branch_id=p_branch_id
   and ba.user_id=p_assignee_id and ba.employment_status='active'
   and (ba.ends_on is null or ba.ends_on>=current_date)) then
   raise exception 'BRANCH_OPS_ASSIGNEE_INVALID' using errcode='23514';
 end if;
 select * into v_row from public.branch_ops_tasks where tenant_id=p_tenant_id and idempotency_key=p_idempotency_key;
 if found then return jsonb_build_object('status','duplicate','taskId',v_row.id); end if;
 insert into public.branch_ops_tasks(tenant_id,branch_id,title,description,due_at,assignee_user_id,priority,source_type,source_id,idempotency_key,created_by)
 values(p_tenant_id,p_branch_id,p_title,p_description,p_due_at,p_assignee_id,p_priority,coalesce(p_source_type,'manual'),p_source_id,p_idempotency_key,p_actor_id)
 returning * into v_row;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_id,'branch.task.created','branch_ops_task',v_row.id::text,jsonb_build_object('tenant_id',p_tenant_id,'branch_id',p_branch_id,'idempotency_key',p_idempotency_key));
 return jsonb_build_object('status','created','taskId',v_row.id);
end $$;

create or replace function public.branch_ops_record_incident(
 p_tenant_id uuid,p_branch_id uuid,p_actor_id uuid,p_idempotency_key text,p_category text,p_description text,
 p_severity text,p_occurred_at timestamptz,p_evidence_asset_ids uuid[]
) returns jsonb language plpgsql security invoker set search_path=public,pg_temp as $$
declare v_incident public.branch_ops_incidents; v_task public.branch_ops_tasks; v_count integer;
begin
 perform public.branch_ops_assert_actor(p_tenant_id,p_branch_id,p_actor_id);
 select * into v_incident from public.branch_ops_incidents where tenant_id=p_tenant_id and idempotency_key=p_idempotency_key;
 if found then return jsonb_build_object('status','duplicate','incidentId',v_incident.id,'escalationTaskId',v_incident.escalation_task_id); end if;
 if p_severity='critical' and coalesce(cardinality(p_evidence_asset_ids),0)=0 then raise exception 'BRANCH_INCIDENT_EVIDENCE_REQUIRED'; end if;
 select count(*) into v_count from public.branch_ops_evidence_assets e
 where e.tenant_id=p_tenant_id and e.branch_id=p_branch_id and e.owner_user_id=p_actor_id
   and e.id=any(coalesce(p_evidence_asset_ids,'{}'::uuid[]))
   and e.purpose='branch_incident' and e.retention_until>now();
 if v_count<>coalesce(cardinality(p_evidence_asset_ids),0) then raise exception 'BRANCH_EVIDENCE_OWNERSHIP_UNVERIFIED' using errcode='42501'; end if;
 insert into public.branch_ops_incidents(tenant_id,branch_id,category,description,severity,occurred_at,evidence_asset_ids,idempotency_key,created_by)
 values(p_tenant_id,p_branch_id,p_category,p_description,p_severity,p_occurred_at,coalesce(p_evidence_asset_ids,'{}'::uuid[]),p_idempotency_key,p_actor_id)
 returning * into v_incident;
 if p_severity in ('high','critical') then
   insert into public.branch_ops_tasks(tenant_id,branch_id,title,description,due_at,assignee_user_id,priority,source_type,source_id,idempotency_key,created_by)
   values(p_tenant_id,p_branch_id,'Incident escalation: '||p_category,p_description,now()+interval '1 hour',p_actor_id,p_severity,'branch_incident',v_incident.id,left(p_idempotency_key,88)||':escalation:'||substr(md5(p_idempotency_key),1,16),p_actor_id)
   returning * into v_task;
   update public.branch_ops_incidents set escalation_task_id=v_task.id where id=v_incident.id;
 end if;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_id,'branch.incident.recorded','branch_ops_incident',v_incident.id::text,jsonb_build_object('tenant_id',p_tenant_id,'branch_id',p_branch_id,'severity',p_severity,'escalation_task_id',v_task.id));
 return jsonb_build_object('status','recorded','incidentId',v_incident.id,'escalationTaskId',v_task.id);
end $$;

create or replace function public.branch_ops_create_maintenance_order(
 p_tenant_id uuid,p_branch_id uuid,p_actor_id uuid,p_equipment_id uuid,p_idempotency_key text,
 p_maintenance_type text,p_scheduled_at timestamptz,p_description text,p_assigned_to uuid,p_evidence_asset_ids uuid[]
) returns jsonb language plpgsql security invoker set search_path=public,pg_temp as $$
declare v_row public.branch_ops_work_orders;
begin
 perform public.branch_ops_assert_actor(p_tenant_id,p_branch_id,p_actor_id);
 if not exists(select 1 from public.branch_ops_equipment e where e.id=p_equipment_id
   and e.tenant_id=p_tenant_id and e.branch_id=p_branch_id and e.status<>'retired') then
   raise exception 'BRANCH_EQUIPMENT_SCOPE_OR_STATUS_INVALID' using errcode='23514';
 end if;
 if p_assigned_to is not null and not exists(select 1 from public.branch_assignments ba
   where ba.branch_id=p_branch_id and ba.user_id=p_assigned_to and ba.employment_status='active'
   and (ba.ends_on is null or ba.ends_on>=current_date)) then raise exception 'BRANCH_OPS_ASSIGNEE_INVALID'; end if;
 if coalesce(cardinality(p_evidence_asset_ids),0)>0 and
   (select count(*) from public.branch_ops_evidence_assets e
    where e.tenant_id=p_tenant_id and e.branch_id=p_branch_id and e.owner_user_id=p_actor_id
      and e.purpose='branch_maintenance' and e.retention_until>now()
      and e.id=any(p_evidence_asset_ids))<>cardinality(p_evidence_asset_ids) then
   raise exception 'BRANCH_MAINTENANCE_EVIDENCE_UNVERIFIED' using errcode='42501';
 end if;
 select * into v_row from public.branch_ops_work_orders where tenant_id=p_tenant_id and idempotency_key=p_idempotency_key;
 if found then return jsonb_build_object('status','duplicate','workOrderId',v_row.id); end if;
 insert into public.branch_ops_work_orders(tenant_id,branch_id,equipment_id,maintenance_type,scheduled_at,description,assigned_to,evidence_asset_ids,idempotency_key,created_by)
 values(p_tenant_id,p_branch_id,p_equipment_id,p_maintenance_type,p_scheduled_at,p_description,p_assigned_to,coalesce(p_evidence_asset_ids,'{}'::uuid[]),p_idempotency_key,p_actor_id)
 returning * into v_row;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_id,'branch.maintenance.created','branch_ops_work_order',v_row.id::text,jsonb_build_object('tenant_id',p_tenant_id,'branch_id',p_branch_id,'equipment_id',p_equipment_id));
 return jsonb_build_object('status','created','workOrderId',v_row.id);
end $$;

create or replace function public.branch_ops_register_evidence_asset(
 p_tenant_id uuid,p_branch_id uuid,p_actor_id uuid,p_object_path text,p_purpose text,p_mime_type text,p_size_bytes bigint
) returns uuid language plpgsql security invoker set search_path=public,pg_temp as $$
declare v_id uuid; v_metadata jsonb;
begin
 perform public.branch_ops_assert_actor(p_tenant_id,p_branch_id,p_actor_id);
 if not exists(select 1 from storage.buckets where id='branch-ops-evidence' and public=false) then raise exception 'BRANCH_EVIDENCE_BUCKET_NOT_PRIVATE'; end if;
 if p_object_path not like p_tenant_id::text||'/'||p_branch_id::text||'/'||p_actor_id::text||'/%' then raise exception 'BRANCH_EVIDENCE_PATH_SCOPE_INVALID'; end if;
 select metadata into v_metadata from storage.objects where bucket_id='branch-ops-evidence' and name=p_object_path;
 if not found then raise exception 'BRANCH_EVIDENCE_STORAGE_OBJECT_MISSING' using errcode='P0002'; end if;
 if p_mime_type not in ('image/jpeg','image/png','application/pdf') or p_size_bytes not between 1 and 8388608 then raise exception 'BRANCH_EVIDENCE_FILE_INVALID'; end if;
 insert into public.branch_ops_evidence_assets(tenant_id,branch_id,object_path,owner_user_id,purpose,mime_type,size_bytes,retention_until)
 values(p_tenant_id,p_branch_id,p_object_path,p_actor_id,p_purpose,p_mime_type,p_size_bytes,now()+interval '365 days')
 on conflict(object_path) do nothing returning id into v_id;
 if v_id is null then select id into v_id from public.branch_ops_evidence_assets where object_path=p_object_path and tenant_id=p_tenant_id and branch_id=p_branch_id and owner_user_id=p_actor_id; end if;
 if v_id is null then raise exception 'BRANCH_EVIDENCE_REGISTER_FAILED'; end if;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_id,'branch.evidence.registered','branch_ops_evidence_asset',v_id::text,
   jsonb_build_object('tenant_id',p_tenant_id,'branch_id',p_branch_id,'purpose',p_purpose,'object_path',p_object_path,'retention_until',now()+interval '365 days'));
 return v_id;
end $$;

create or replace function public.branch_ops_publish_compliance_snapshot(
 p_tenant_id uuid,p_branch_id uuid,p_actor_id uuid,p_period_start date,p_period_end date,p_idempotency_key text,p_source_revision text
) returns jsonb language plpgsql security invoker set search_path=public,pg_temp as $$
declare v_count integer; v_pass integer; v_weight numeric; v_score numeric; v_ids uuid[]; v_source_revision text; v_row public.branch_ops_compliance_snapshots;
begin
 perform public.branch_ops_assert_approver(p_tenant_id,p_branch_id,p_actor_id);
 select * into v_row from public.branch_ops_compliance_snapshots where tenant_id=p_tenant_id and idempotency_key=p_idempotency_key;
 if found then return jsonb_build_object('status','duplicate','snapshotId',v_row.id,'score',v_row.score); end if;
 select count(*),coalesce(sum(weight) filter(where result='pass'),0),coalesce(sum(weight) filter(where result in ('pass','fail')),0),
   array_agg(evidence_asset_id),
   md5(coalesce(string_agg(concat_ws('|',id::text,check_key,title,weight::text,result,status,
     evidence_asset_id::text,created_by::text,approved_by::text,approved_at::text),chr(10)
     order by business_date,check_key,id),''))
 into v_count,v_pass,v_weight,v_ids,v_source_revision
 from public.branch_ops_compliance_checks
 where tenant_id=p_tenant_id and branch_id=p_branch_id and business_date between p_period_start and p_period_end
   and status='approved' and result in ('pass','fail','not_applicable');
 if v_count=0 or exists(select 1 from public.branch_ops_compliance_checks
   where tenant_id=p_tenant_id and branch_id=p_branch_id and business_date between p_period_start and p_period_end
     and status<>'approved') then raise exception 'BRANCH_COMPLIANCE_EVIDENCE_INCOMPLETE'; end if;
 if exists(select 1 from public.branch_ops_compliance_checks c where c.tenant_id=p_tenant_id and c.branch_id=p_branch_id
   and c.business_date between p_period_start and p_period_end and c.status='approved'
   and (c.evidence_asset_id is null or not exists(select 1 from public.branch_ops_evidence_assets e
     where e.id=c.evidence_asset_id and e.tenant_id=p_tenant_id and e.branch_id=p_branch_id
       and e.purpose='branch_compliance' and e.retention_until>now()))) then
   raise exception 'BRANCH_COMPLIANCE_EVIDENCE_UNVERIFIED';
 end if;
 if v_weight<=0 then raise exception 'BRANCH_COMPLIANCE_NO_APPLICABLE_CHECKS'; end if;
 if p_source_revision is not null and p_source_revision<>'' and p_source_revision<>v_source_revision then
   raise exception 'BRANCH_COMPLIANCE_SOURCE_REVISION_MISMATCH' using errcode='40001';
 end if;
 v_score:=round((v_pass/v_weight)*100,2);
 insert into public.branch_ops_compliance_snapshots(tenant_id,branch_id,period_start,period_end,score,completed_checks,required_checks,evidence_asset_ids,source_revision,idempotency_key,published_by)
 values(p_tenant_id,p_branch_id,p_period_start,p_period_end,v_score,v_count,v_count,coalesce(v_ids,'{}'::uuid[]),v_source_revision,p_idempotency_key,p_actor_id)
 returning * into v_row;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_id,'branch.compliance.published','branch_ops_compliance_snapshot',v_row.id::text,jsonb_build_object('tenant_id',p_tenant_id,'branch_id',p_branch_id,'score',v_score,'checks',v_count));
 return jsonb_build_object('status','published','snapshotId',v_row.id,'score',v_score);
end $$;


create or replace function public.branch_ops_submit_compliance_check(
 p_tenant_id uuid,p_branch_id uuid,p_actor_id uuid,p_check_key text,p_title text,p_weight integer,
 p_business_date date,p_evidence_asset_id uuid
) returns jsonb language plpgsql security invoker set search_path=public,pg_temp as $$
declare v_row public.branch_ops_compliance_checks;
begin
 perform public.branch_ops_assert_actor(p_tenant_id,p_branch_id,p_actor_id);
 if not exists(select 1 from public.branch_ops_evidence_assets e where e.id=p_evidence_asset_id
   and e.tenant_id=p_tenant_id and e.branch_id=p_branch_id and e.owner_user_id=p_actor_id
   and e.purpose='branch_compliance' and e.retention_until>now()) then
   raise exception 'BRANCH_COMPLIANCE_EVIDENCE_UNVERIFIED' using errcode='42501';
 end if;
 insert into public.branch_ops_compliance_checks(tenant_id,branch_id,check_key,title,weight,result,status,evidence_asset_id,business_date,created_by)
 values(p_tenant_id,p_branch_id,p_check_key,p_title,p_weight,'pending','submitted',p_evidence_asset_id,p_business_date,p_actor_id)
 on conflict(tenant_id,branch_id,check_key,business_date) do update
   set title=excluded.title,weight=excluded.weight,result='pending',status='submitted',
       evidence_asset_id=excluded.evidence_asset_id,created_by=excluded.created_by,
       approved_by=null,approved_at=null,updated_at=now()
   where public.branch_ops_compliance_checks.status in ('draft','rejected')
 returning * into v_row;
 if v_row.id is null then raise exception 'BRANCH_COMPLIANCE_CHECK_ALREADY_REVIEWED' using errcode='55000'; end if;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_id,'branch.compliance.check.submitted','branch_ops_compliance_check',v_row.id::text,
   jsonb_build_object('tenant_id',p_tenant_id,'branch_id',p_branch_id,'check_key',p_check_key));
 return jsonb_build_object('status','submitted','checkId',v_row.id);
end $$;

create or replace function public.branch_ops_review_compliance_check(
 p_tenant_id uuid,p_branch_id uuid,p_actor_id uuid,p_check_id uuid,p_result text
) returns jsonb language plpgsql security invoker set search_path=public,pg_temp as $$
declare v_row public.branch_ops_compliance_checks;
begin
 perform public.branch_ops_assert_approver(p_tenant_id,p_branch_id,p_actor_id);
 select * into v_row from public.branch_ops_compliance_checks
 where id=p_check_id and tenant_id=p_tenant_id and branch_id=p_branch_id for update;
 if not found then raise exception 'BRANCH_COMPLIANCE_CHECK_NOT_FOUND' using errcode='P0002'; end if;
 if v_row.status<>'submitted' then raise exception 'BRANCH_COMPLIANCE_CHECK_NOT_SUBMITTED' using errcode='55000'; end if;
 if v_row.created_by=p_actor_id then raise exception 'BRANCH_COMPLIANCE_SEPARATION_OF_DUTIES' using errcode='42501'; end if;
 if p_result not in ('pass','fail','not_applicable') then raise exception 'BRANCH_COMPLIANCE_RESULT_INVALID'; end if;
 update public.branch_ops_compliance_checks set status='approved',result=p_result,approved_by=p_actor_id,approved_at=now(),updated_at=now()
 where id=p_check_id returning * into v_row;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_id,'branch.compliance.check.reviewed','branch_ops_compliance_check',v_row.id::text,
   jsonb_build_object('tenant_id',p_tenant_id,'branch_id',p_branch_id,'result',p_result,'submitted_by',v_row.created_by));
 return jsonb_build_object('status','approved','checkId',v_row.id,'result',p_result);
end $$;


create or replace function public.branch_ops_register_equipment(
 p_tenant_id uuid,p_branch_id uuid,p_actor_id uuid,p_asset_code text,p_name text
) returns jsonb language plpgsql security invoker set search_path=public,pg_temp as $$
declare v_row public.branch_ops_equipment;
begin
 perform public.branch_ops_assert_approver(p_tenant_id,p_branch_id,p_actor_id);
 insert into public.branch_ops_equipment(tenant_id,branch_id,asset_code,name)
 values(p_tenant_id,p_branch_id,p_asset_code,p_name)
 on conflict(tenant_id,branch_id,asset_code) do update set name=excluded.name,updated_at=now()
 where public.branch_ops_equipment.status<>'retired'
 returning * into v_row;
 if v_row.id is null then raise exception 'BRANCH_EQUIPMENT_RETIRED_OR_CONFLICT' using errcode='55000'; end if;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_id,'branch.equipment.registered','branch_ops_equipment',v_row.id::text,
   jsonb_build_object('tenant_id',p_tenant_id,'branch_id',p_branch_id,'asset_code',p_asset_code));
 return jsonb_build_object('status','registered','equipmentId',v_row.id);
end $$;

create or replace function public.branch_ops_update_task_status(
 p_tenant_id uuid,p_branch_id uuid,p_actor_id uuid,p_task_id uuid,p_status text
) returns jsonb language plpgsql security invoker set search_path=public,pg_temp as $$
declare v_row public.branch_ops_tasks;
begin
 perform public.branch_ops_assert_actor(p_tenant_id,p_branch_id,p_actor_id);
 select * into v_row from public.branch_ops_tasks where id=p_task_id and tenant_id=p_tenant_id and branch_id=p_branch_id for update;
 if not found then raise exception 'BRANCH_TASK_NOT_FOUND' using errcode='P0002'; end if;
 if v_row.assignee_user_id<>p_actor_id then perform public.branch_ops_assert_approver(p_tenant_id,p_branch_id,p_actor_id); end if;
 if not ((v_row.status='open' and p_status in ('in_progress','completed','cancelled'))
   or (v_row.status='in_progress' and p_status in ('completed','cancelled'))) then
   raise exception 'BRANCH_TASK_TRANSITION_INVALID' using errcode='55000';
 end if;
 update public.branch_ops_tasks set status=p_status,completed_at=case when p_status='completed' then now() else null end,updated_at=now()
 where id=p_task_id returning * into v_row;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_id,'branch.task.status_changed','branch_ops_task',v_row.id::text,
   jsonb_build_object('tenant_id',p_tenant_id,'branch_id',p_branch_id,'status',p_status));
 return jsonb_build_object('status',v_row.status,'taskId',v_row.id);
end $$;

create or replace function public.branch_ops_update_incident_status(
 p_tenant_id uuid,p_branch_id uuid,p_actor_id uuid,p_incident_id uuid,p_status text
) returns jsonb language plpgsql security invoker set search_path=public,pg_temp as $$
declare v_row public.branch_ops_incidents;
begin
 perform public.branch_ops_assert_approver(p_tenant_id,p_branch_id,p_actor_id);
 select * into v_row from public.branch_ops_incidents where id=p_incident_id and tenant_id=p_tenant_id and branch_id=p_branch_id for update;
 if not found then raise exception 'BRANCH_INCIDENT_NOT_FOUND' using errcode='P0002'; end if;
 if not ((v_row.status='open' and p_status in ('investigating','resolved'))
   or (v_row.status='investigating' and p_status='resolved')
   or (v_row.status='resolved' and p_status='closed')) then
   raise exception 'BRANCH_INCIDENT_TRANSITION_INVALID' using errcode='55000';
 end if;
 update public.branch_ops_incidents set status=p_status,updated_at=now() where id=p_incident_id returning * into v_row;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_id,'branch.incident.status_changed','branch_ops_incident',v_row.id::text,
   jsonb_build_object('tenant_id',p_tenant_id,'branch_id',p_branch_id,'status',p_status));
 return jsonb_build_object('status',v_row.status,'incidentId',v_row.id);
end $$;

create or replace function public.branch_ops_update_work_order_status(
 p_tenant_id uuid,p_branch_id uuid,p_actor_id uuid,p_work_order_id uuid,p_status text
) returns jsonb language plpgsql security invoker set search_path=public,pg_temp as $$
declare v_row public.branch_ops_work_orders;
begin
 perform public.branch_ops_assert_actor(p_tenant_id,p_branch_id,p_actor_id);
 select * into v_row from public.branch_ops_work_orders where id=p_work_order_id and tenant_id=p_tenant_id and branch_id=p_branch_id for update;
 if not found then raise exception 'BRANCH_WORK_ORDER_NOT_FOUND' using errcode='P0002'; end if;
 if v_row.assigned_to is distinct from p_actor_id then perform public.branch_ops_assert_approver(p_tenant_id,p_branch_id,p_actor_id); end if;
 if not ((v_row.status='scheduled' and p_status in ('in_progress','cancelled'))
   or (v_row.status='in_progress' and p_status in ('completed','cancelled'))) then
   raise exception 'BRANCH_WORK_ORDER_TRANSITION_INVALID' using errcode='55000';
 end if;
 update public.branch_ops_work_orders set status=p_status,updated_at=now() where id=p_work_order_id returning * into v_row;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_id,'branch.maintenance.status_changed','branch_ops_work_order',v_row.id::text,
   jsonb_build_object('tenant_id',p_tenant_id,'branch_id',p_branch_id,'status',p_status));
 return jsonb_build_object('status',v_row.status,'workOrderId',v_row.id);
end $$;

revoke all on function public.branch_ops_register_equipment(uuid,uuid,uuid,text,text) from public,anon,authenticated;
revoke all on function public.branch_ops_update_task_status(uuid,uuid,uuid,uuid,text) from public,anon,authenticated;
revoke all on function public.branch_ops_update_incident_status(uuid,uuid,uuid,uuid,text) from public,anon,authenticated;
revoke all on function public.branch_ops_update_work_order_status(uuid,uuid,uuid,uuid,text) from public,anon,authenticated;
revoke all on function public.branch_ops_assert_actor(uuid,uuid,uuid) from public,anon,authenticated;
revoke all on function public.branch_ops_assert_approver(uuid,uuid,uuid) from public,anon,authenticated;
revoke all on function public.branch_ops_create_task(uuid,uuid,uuid,uuid,text,text,text,timestamptz,text,text,uuid) from public,anon,authenticated;
revoke all on function public.branch_ops_record_incident(uuid,uuid,uuid,text,text,text,text,timestamptz,uuid[]) from public,anon,authenticated;
revoke all on function public.branch_ops_create_maintenance_order(uuid,uuid,uuid,uuid,text,text,timestamptz,text,uuid,uuid[]) from public,anon,authenticated;
revoke all on function public.branch_ops_register_evidence_asset(uuid,uuid,uuid,text,text,text,bigint) from public,anon,authenticated;
revoke all on function public.branch_ops_publish_compliance_snapshot(uuid,uuid,uuid,date,date,text,text) from public,anon,authenticated;
revoke all on function public.branch_ops_submit_compliance_check(uuid,uuid,uuid,text,text,integer,date,uuid) from public,anon,authenticated;
revoke all on function public.branch_ops_review_compliance_check(uuid,uuid,uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.branch_ops_register_equipment(uuid,uuid,uuid,text,text) to service_role;
grant execute on function public.branch_ops_update_task_status(uuid,uuid,uuid,uuid,text) to service_role;
grant execute on function public.branch_ops_update_incident_status(uuid,uuid,uuid,uuid,text) to service_role;
grant execute on function public.branch_ops_update_work_order_status(uuid,uuid,uuid,uuid,text) to service_role;
grant execute on function public.branch_ops_assert_actor(uuid,uuid,uuid) to service_role;
grant execute on function public.branch_ops_assert_approver(uuid,uuid,uuid) to service_role;
grant execute on function public.branch_ops_create_task(uuid,uuid,uuid,uuid,text,text,text,timestamptz,text,text,uuid) to service_role;
grant execute on function public.branch_ops_record_incident(uuid,uuid,uuid,text,text,text,text,timestamptz,uuid[]) to service_role;
grant execute on function public.branch_ops_create_maintenance_order(uuid,uuid,uuid,uuid,text,text,timestamptz,text,uuid) to service_role;
grant execute on function public.branch_ops_register_evidence_asset(uuid,uuid,uuid,text,text,text,bigint) to service_role;
grant execute on function public.branch_ops_publish_compliance_snapshot(uuid,uuid,uuid,date,date,text,text) to service_role;
grant execute on function public.branch_ops_submit_compliance_check(uuid,uuid,uuid,text,text,integer,date,uuid) to service_role;
grant execute on function public.branch_ops_review_compliance_check(uuid,uuid,uuid,uuid,text) to service_role;
