-- T02 / D01-F07: unified approval inbox with source-entity transitions.
-- Source migration. Apply only to the staging project after review.
begin;
create table if not exists public.executive_approval_policies(
 tenant_id uuid not null references public.tenants(id) on delete restrict,category text not null check(category in ('procurement','finance','hr','branch_ops')),
 required_roles text[] not null check(cardinality(required_roles)>0),allow_self_approval boolean not null default false,
 expiry_after interval not null default interval '48 hours' check(expiry_after>interval '0 seconds' and expiry_after<=interval '30 days'),
 enabled boolean not null default true,updated_by uuid references auth.users(id),updated_at timestamptz not null default now(),
 primary key(tenant_id,category)
);
create table if not exists public.executive_approval_requests(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete restrict,
 category text not null check(category in ('procurement','finance','hr','branch_ops')),entity_type text not null,
 entity_id uuid not null,branch_id uuid,created_by uuid not null references auth.users(id) on delete restrict,
 amount_idr bigint not null default 0 check(amount_idr>=0),reason text,required_roles text[] not null,
 allow_self_approval boolean not null default false,source_version integer not null default 1,
 status text not null default 'pending' check(status in ('pending','claimed','approved','rejected','expired')),
 expires_at timestamptz not null,claimed_by uuid references auth.users(id),claimed_at timestamptz,claim_expires_at timestamptz,
 decided_by uuid references auth.users(id),decided_at timestamptz,decision_reason text,version integer not null default 1 check(version>0),
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 unique(tenant_id,entity_type,entity_id),
 foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict
);
create index if not exists executive_approval_inbox_idx on public.executive_approval_requests(tenant_id,status,expires_at,category,branch_id);
create table if not exists public.executive_approval_delegations(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete restrict,
 delegator_user_id uuid not null references auth.users(id) on delete restrict,delegate_user_id uuid not null references auth.users(id) on delete restrict,
 category text not null check(category in ('procurement','finance','hr','branch_ops')),branch_id uuid,
 starts_at timestamptz not null,ends_at timestamptz not null,approved_by uuid references auth.users(id),approved_at timestamptz,
 revoked_at timestamptz,created_at timestamptz not null default now(),
 foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict,
 check(delegator_user_id<>delegate_user_id),check(ends_at>starts_at)
);
create index if not exists executive_approval_delegation_lookup_idx on public.executive_approval_delegations(tenant_id,delegate_user_id,category,starts_at,ends_at) where revoked_at is null;
create table if not exists public.executive_approval_decisions(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete restrict,
 approval_id uuid not null references public.executive_approval_requests(id) on delete restrict,
 actor_user_id uuid not null references auth.users(id) on delete restrict,decision text not null check(decision in ('approve','reject')),
 reason text not null,source_version integer not null,delegated_by uuid references auth.users(id),created_at timestamptz not null default now()
);
create index if not exists executive_approval_decisions_history_idx on public.executive_approval_decisions(tenant_id,approval_id,created_at);

alter table public.executive_approval_policies enable row level security;
alter table public.executive_approval_policies force row level security;
alter table public.executive_approval_requests enable row level security;
alter table public.executive_approval_requests force row level security;
alter table public.executive_approval_delegations enable row level security;
alter table public.executive_approval_delegations force row level security;
alter table public.executive_approval_decisions enable row level security;
alter table public.executive_approval_decisions force row level security;
do $$ declare t text; begin
 foreach t in array array['executive_approval_policies','executive_approval_requests','executive_approval_delegations','executive_approval_decisions'] loop
  execute format('drop policy if exists service_role_only on public.%I',t);
  execute format('create policy service_role_only on public.%I for all to service_role using(true) with check(true)',t);
  execute format('revoke all on public.%I from public,anon,authenticated',t);
  execute format('grant select,insert,update,delete on public.%I to service_role',t);
 end loop;
end $$;

insert into public.executive_approval_policies(tenant_id,category,required_roles,allow_self_approval)
select t.id,p.category,p.roles,false from public.tenants t cross join (values
 ('procurement',array['tenant_owner','branch_manager']::text[]),
 ('finance',array['tenant_owner']::text[]),
 ('hr',array['tenant_owner']::text[]),
 ('branch_ops',array['tenant_owner','branch_manager']::text[])
) p(category,roles)
on conflict(tenant_id,category) do nothing;

create or replace function public.trg_seed_executive_approval_policies()
returns trigger language plpgsql security definer set search_path=''
as $ begin
 insert into public.executive_approval_policies(tenant_id,category,required_roles,allow_self_approval)
 values
 (new.id,'procurement',array['tenant_owner','branch_manager']::text[],false),
 (new.id,'finance',array['tenant_owner']::text[],false),
 (new.id,'hr',array['tenant_owner']::text[],false),
 (new.id,'branch_ops',array['tenant_owner','branch_manager']::text[],false)
 on conflict(tenant_id,category) do nothing;
 return new;
end $;
drop trigger if exists seed_executive_approval_policies on public.tenants;
create trigger seed_executive_approval_policies after insert on public.tenants
for each row execute function public.trg_seed_executive_approval_policies();

create or replace function public.enqueue_executive_approval(
 p_tenant_id uuid,p_category text,p_entity_type text,p_entity_id uuid,p_branch_id uuid,p_created_by uuid,p_amount_idr bigint,p_reason text
) returns uuid language plpgsql security definer set search_path=''
as $$
declare v_policy public.executive_approval_policies%rowtype;v_id uuid;
begin
 select * into v_policy from public.executive_approval_policies where tenant_id=p_tenant_id and category=p_category and enabled;
 if not found then return null;end if;
 insert into public.executive_approval_requests(tenant_id,category,entity_type,entity_id,branch_id,created_by,amount_idr,reason,
  required_roles,allow_self_approval,expires_at)
 values(p_tenant_id,p_category,p_entity_type,p_entity_id,p_branch_id,p_created_by,greatest(coalesce(p_amount_idr,0),0),
  left(coalesce(p_reason,''),1000),v_policy.required_roles,v_policy.allow_self_approval,now()+v_policy.expiry_after)
 on conflict(tenant_id,entity_type,entity_id) do update set
  status='pending',created_by=excluded.created_by,amount_idr=excluded.amount_idr,reason=excluded.reason,
  required_roles=excluded.required_roles,allow_self_approval=excluded.allow_self_approval,
  expires_at=excluded.expires_at,claimed_by=null,claimed_at=null,claim_expires_at=null,decided_by=null,decided_at=null,
  decision_reason=null,source_version=public.executive_approval_requests.source_version+1,
  version=public.executive_approval_requests.version+1,updated_at=now()
 where public.executive_approval_requests.status in ('rejected','expired')
 returning id into v_id;
 if v_id is null then select id into v_id from public.executive_approval_requests where tenant_id=p_tenant_id and entity_type=p_entity_type and entity_id=p_entity_id;end if;
 return v_id;
end $$;

create or replace function public.trg_enqueue_purchase_requisition_approval()
returns trigger language plpgsql security definer set search_path=''
as $ declare v_tenant_id uuid;begin
 if new.status='submitted' and (tg_op='INSERT' or old.status is distinct from new.status) then
  select tenant_id into v_tenant_id from public.branches where id=new.branch_id;
  if v_tenant_id is not null then
   perform public.enqueue_executive_approval(v_tenant_id,'procurement','purchase_requisition',new.id,new.branch_id,new.requested_by,new.estimated_total_idr,new.purpose);
  end if;
 end if;return new;end $;
drop trigger if exists enqueue_purchase_requisition_approval on public.purchase_requisitions;
create trigger enqueue_purchase_requisition_approval after insert or update of status on public.purchase_requisitions
for each row execute function public.trg_enqueue_purchase_requisition_approval();

create or replace function public.trg_enqueue_refund_approval()
returns trigger language plpgsql security definer set search_path=''
as $$ declare v_branch uuid;v_tenant uuid;begin
 if new.status='requested' and (tg_op='INSERT' or old.status is distinct from new.status) then
  v_branch:=new.branch_id;
  if v_branch is null and new.pos_sale_id is not null then select s.branch_id into v_branch from public.pos_sales s where s.id=new.pos_sale_id;end if;
  if v_branch is null and new.order_id is not null then select o.branch_id into v_branch from public.orders o where o.id=new.order_id;end if;
  select b.tenant_id into v_tenant from public.branches b where b.id=v_branch;
  if v_tenant is not null then perform public.enqueue_executive_approval(v_tenant,'finance','refund_record',new.id,v_branch,new.requested_by,new.amount_idr,new.reason);end if;
 end if;return new;end $$;
drop trigger if exists enqueue_refund_approval on public.refund_records;
create trigger enqueue_refund_approval after insert or update of status on public.refund_records
for each row execute function public.trg_enqueue_refund_approval();

create or replace function public.trg_enqueue_payroll_approval()
returns trigger language plpgsql security definer set search_path=''
as $$ begin
 if new.status='submitted' and (tg_op='INSERT' or old.status is distinct from new.status) then
  perform public.enqueue_executive_approval(new.tenant_id,'hr','hr_payroll_run',new.id,new.branch_id,new.created_by,
   coalesce(new.net_amount_idr,new.gross_amount_idr),'Payroll approval '||new.period_start::text||' - '||new.period_end::text);
 end if;return new;end $$;
drop trigger if exists enqueue_payroll_approval on public.hr_payroll_runs;
create trigger enqueue_payroll_approval after insert or update of status on public.hr_payroll_runs
for each row execute function public.trg_enqueue_payroll_approval();

create or replace function public.trg_enqueue_branch_compliance_approval()
returns trigger language plpgsql security definer set search_path=''
as $$ begin
 if new.status='submitted' and (tg_op='INSERT' or old.status is distinct from new.status) then
  perform public.enqueue_executive_approval(new.tenant_id,'branch_ops','branch_ops_compliance_check',new.id,new.branch_id,new.created_by,0,new.check_key||': '||new.title);
 end if;return new;end $$;
drop trigger if exists enqueue_branch_compliance_approval on public.branch_ops_compliance_checks;
create trigger enqueue_branch_compliance_approval after insert or update of status on public.branch_ops_compliance_checks
for each row execute function public.trg_enqueue_branch_compliance_approval();

create or replace function public.list_pending_approvals(
 p_actor_user_id uuid,p_tenant_id uuid,p_branch_ids uuid[],p_categories text[] default null
) returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_rows jsonb;v_role text;
begin
 if coalesce(current_setting('request.jwt.claim.role',true),'')<>'service_role' then raise exception using errcode='42501',message='APPROVAL_SERVICE_ROLE_REQUIRED';end if;
 select role into v_role from public.tenant_memberships where tenant_id=p_tenant_id and user_id=p_actor_user_id and status='active';
 if v_role is null then raise exception using errcode='42501',message='APPROVAL_TENANT_MEMBERSHIP_REQUIRED';end if;
 if exists(select 1 from unnest(coalesce(p_branch_ids,'{}'::uuid[])) x where not exists(select 1 from public.branches b where b.id=x and b.tenant_id=p_tenant_id))
  then raise exception using errcode='42501',message='APPROVAL_BRANCH_SCOPE_DENIED';end if;
 update public.executive_approval_requests set status='expired',version=version+1,updated_at=now()
 where tenant_id=p_tenant_id and status in ('pending','claimed') and expires_at<=now();
 select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'tenant_id',a.tenant_id,'category',a.category,'source_entity',a.entity_type,
  'source_entity_id',a.entity_id,'branch_id',a.branch_id,'created_by',a.created_by,'amount_idr',a.amount_idr,'status',a.status,
  'source_version',a.source_version,'version',a.version,'expires_at',a.expires_at,'claimed_by',a.claimed_by,
  'claim_expires_at',a.claim_expires_at,'required_roles',a.required_roles,'reason',a.reason)
  order by a.expires_at asc,a.amount_idr desc),'[]'::jsonb) into v_rows
 from public.executive_approval_requests a
 where a.tenant_id=p_tenant_id and a.status in ('pending','claimed')
  and ((a.branch_id is not null and a.branch_id=any(coalesce(p_branch_ids,'{}'::uuid[]))) or (a.branch_id is null and v_role='tenant_owner'))
  and (p_categories is null or a.category=any(p_categories))
  and (v_role=any(a.required_roles) or exists(
   select 1 from public.executive_approval_delegations d join public.tenant_memberships dm
    on dm.tenant_id=d.tenant_id and dm.user_id=d.delegator_user_id and dm.status='active'
   where d.tenant_id=a.tenant_id and d.delegate_user_id=p_actor_user_id and d.category=a.category
    and (d.branch_id is null or d.branch_id is not distinct from a.branch_id)
    and d.approved_at is not null and d.revoked_at is null and now() between d.starts_at and d.ends_at
    and dm.role=any(a.required_roles)
  ));
 return jsonb_build_object('approvals',v_rows);
end $$;

create or replace function public.claim_approval(
 p_actor_user_id uuid,p_tenant_id uuid,p_branch_ids uuid[],p_approval_id uuid,p_expected_version integer
) returns jsonb language plpgsql security definer set search_path=''
as $$
declare a public.executive_approval_requests%rowtype;v_role text;v_delegator uuid;v_delegator_role text;v_limit bigint;
begin
 if coalesce(current_setting('request.jwt.claim.role',true),'')<>'service_role' then raise exception using errcode='42501',message='APPROVAL_SERVICE_ROLE_REQUIRED';end if;
 select role into v_role from public.tenant_memberships where tenant_id=p_tenant_id and user_id=p_actor_user_id and status='active';
 if v_role is null then raise exception using errcode='42501',message='APPROVAL_TENANT_MEMBERSHIP_REQUIRED';end if;
 select * into a from public.executive_approval_requests where id=p_approval_id and tenant_id=p_tenant_id for update;
 if not found then raise exception using errcode='P0002',message='APPROVAL_NOT_FOUND';end if;
 if (a.branch_id is not null and not (a.branch_id=any(coalesce(p_branch_ids,'{}'::uuid[])))) or (a.branch_id is null and v_role<>'tenant_owner') then raise exception using errcode='42501',message='APPROVAL_BRANCH_SCOPE_DENIED';end if;
 if a.version<>p_expected_version then raise exception using errcode='40001',message='APPROVAL_STALE_VERSION';end if;
 if a.status not in ('pending','claimed') or a.expires_at<=now() then raise exception using errcode='55000',message='APPROVAL_NOT_PENDING_OR_EXPIRED';end if;
 if a.created_by=p_actor_user_id and not a.allow_self_approval then raise exception using errcode='42501',message='APPROVAL_SELF_APPROVAL_DENIED';end if;
 if not (v_role=any(a.required_roles)) then
  select d.delegator_user_id into v_delegator from public.executive_approval_delegations d join public.tenant_memberships dm
   on dm.tenant_id=d.tenant_id and dm.user_id=d.delegator_user_id and dm.status='active'
  where d.tenant_id=p_tenant_id and d.delegate_user_id=p_actor_user_id and d.category=a.category
   and (d.branch_id is null or d.branch_id is not distinct from a.branch_id)
   and d.approved_at is not null and d.revoked_at is null and now() between d.starts_at and d.ends_at
   and dm.role=any(a.required_roles) limit 1;
  if v_delegator is null then raise exception using errcode='42501',message='APPROVAL_ROLE_OR_DELEGATION_REQUIRED';end if;
  select role into v_delegator_role from public.tenant_memberships where tenant_id=p_tenant_id and user_id=v_delegator and status='active';
 end if;
 v_limit:=case when coalesce(v_delegator_role,v_role)='tenant_owner' then 9223372036854775807
  when coalesce((select permissions->>'approval_limit_idr' from public.tenant_memberships where tenant_id=p_tenant_id and user_id=coalesce(v_delegator,p_actor_user_id)),'') ~ '^[0-9]+
 if a.amount_idr>v_limit then raise exception using errcode='42501',message='APPROVAL_AMOUNT_LIMIT';end if;
 if a.status='claimed' and a.claimed_by<>p_actor_user_id and a.claim_expires_at>now() then raise exception using errcode='55P03',message='APPROVAL_CLAIMED_BY_OTHER';end if;
 update public.executive_approval_requests set status='claimed',claimed_by=p_actor_user_id,claimed_at=now(),
  claim_expires_at=least(expires_at,now()+interval '5 minutes'),version=version+1,updated_at=now()
 where id=a.id returning * into a;
 return jsonb_build_object('approval_id',a.id,'claimed_by',a.claimed_by,'claim_expires_at',a.claim_expires_at,'version',a.version,'delegated_by',v_delegator);
end $$;

create or replace function public.decide_approval(
 p_actor_user_id uuid,p_tenant_id uuid,p_branch_ids uuid[],p_approval_id uuid,p_decision text,p_reason text,p_expected_version integer
) returns jsonb language plpgsql security definer set search_path=''
as $$
declare a public.executive_approval_requests%rowtype;v_role text;v_delegator uuid;v_delegator_role text;v_limit bigint;v_updated integer:=0;v_source_version integer;
begin
 if coalesce(current_setting('request.jwt.claim.role',true),'')<>'service_role' then raise exception using errcode='42501',message='APPROVAL_SERVICE_ROLE_REQUIRED';end if;
 if p_decision not in ('approve','reject') or length(btrim(coalesce(p_reason,'')))<8 then raise exception using errcode='22023',message='APPROVAL_DECISION_INPUT_INVALID';end if;
 select role into v_role from public.tenant_memberships where tenant_id=p_tenant_id and user_id=p_actor_user_id and status='active';
 if v_role is null then raise exception using errcode='42501',message='APPROVAL_TENANT_MEMBERSHIP_REQUIRED';end if;
 select * into a from public.executive_approval_requests where id=p_approval_id and tenant_id=p_tenant_id for update;
 if not found then raise exception using errcode='P0002',message='APPROVAL_NOT_FOUND';end if;
 if a.branch_id is not null and not (a.branch_id=any(coalesce(p_branch_ids,'{}'::uuid[]))) then raise exception using errcode='42501',message='APPROVAL_BRANCH_SCOPE_DENIED';end if;
 if a.version<>p_expected_version then raise exception using errcode='40001',message='APPROVAL_STALE_VERSION';end if;
 if a.status not in ('pending','claimed') or a.expires_at<=now() then raise exception using errcode='55000',message='APPROVAL_NOT_PENDING_OR_EXPIRED';end if;
 if a.created_by=p_actor_user_id and not a.allow_self_approval then raise exception using errcode='42501',message='APPROVAL_SELF_APPROVAL_DENIED';end if;
 if not (v_role=any(a.required_roles)) then
  select d.delegator_user_id into v_delegator from public.executive_approval_delegations d join public.tenant_memberships dm
   on dm.tenant_id=d.tenant_id and dm.user_id=d.delegator_user_id and dm.status='active'
  where d.tenant_id=p_tenant_id and d.delegate_user_id=p_actor_user_id and d.category=a.category
   and (d.branch_id is null or d.branch_id is not distinct from a.branch_id)
   and d.approved_at is not null and d.revoked_at is null and now() between d.starts_at and d.ends_at
   and dm.role=any(a.required_roles) limit 1;
  if v_delegator is null then raise exception using errcode='42501',message='APPROVAL_ROLE_OR_DELEGATION_REQUIRED';end if;
  select role into v_delegator_role from public.tenant_memberships where tenant_id=p_tenant_id and user_id=v_delegator and status='active';
 end if;
 v_limit:=case when coalesce(v_delegator_role,v_role)='tenant_owner' then 9223372036854775807
  when coalesce((select permissions->>'approval_limit_idr' from public.tenant_memberships where tenant_id=p_tenant_id and user_id=coalesce(v_delegator,p_actor_user_id)),'') ~ '^[0-9]+
 if a.amount_idr>v_limit then raise exception using errcode='42501',message='APPROVAL_AMOUNT_LIMIT';end if;
 if a.status='claimed' and a.claimed_by<>p_actor_user_id and a.claim_expires_at>now() then raise exception using errcode='55P03',message='APPROVAL_CLAIMED_BY_OTHER';end if;

 if a.entity_type='purchase_requisition' then
  update public.purchase_requisitions set status=case when p_decision='approve' then 'approved' else 'rejected' end,
   approved_by=case when p_decision='approve' then p_actor_user_id else approved_by end,
   approved_at=case when p_decision='approve' then now() else approved_at end,
   rejected_by=case when p_decision='reject' then p_actor_user_id else rejected_by end,
   rejected_at=case when p_decision='reject' then now() else rejected_at end,updated_at=now()
  where id=a.entity_id and status='submitted';
 elsif a.entity_type='refund_record' then
  update public.refund_records set status=case when p_decision='approve' then 'approved' else 'rejected' end,
   reviewed_by=p_actor_user_id,reviewed_at=now()
  where id=a.entity_id and status='requested';
 elsif a.entity_type='hr_payroll_run' then
  update public.hr_payroll_runs set status=case when p_decision='approve' then 'approved' else 'cancelled' end,
   approved_by=case when p_decision='approve' then p_actor_user_id else approved_by end,
   approved_at=case when p_decision='approve' then now() else approved_at end,updated_at=now()
  where id=a.entity_id and tenant_id=p_tenant_id and status='submitted' and created_by<>p_actor_user_id;
 elsif a.entity_type='branch_ops_compliance_check' then
  update public.branch_ops_compliance_checks set status=case when p_decision='approve' then 'approved' else 'rejected' end,
   approved_by=case when p_decision='approve' then p_actor_user_id else approved_by end,
   approved_at=case when p_decision='approve' then now() else approved_at end,updated_at=now()
  where id=a.entity_id and tenant_id=p_tenant_id and status='submitted' and created_by<>p_actor_user_id;
 else raise exception using errcode='22023',message='APPROVAL_SOURCE_TYPE_UNSUPPORTED';
 end if;
 get diagnostics v_updated=row_count;
 if v_updated<>1 then raise exception using errcode='40001',message='APPROVAL_SOURCE_STALE_OR_ALREADY_CHANGED';end if;
 v_source_version:=a.source_version+1;
 update public.executive_approval_requests set status=case when p_decision='approve' then 'approved' else 'rejected' end,
  decided_by=p_actor_user_id,decided_at=now(),decision_reason=left(p_reason,1000),source_version=v_source_version,
  version=version+1,updated_at=now() where id=a.id returning version into a.version;
 insert into public.executive_approval_decisions(tenant_id,approval_id,actor_user_id,decision,reason,source_version,delegated_by)
 values(p_tenant_id,a.id,p_actor_user_id,p_decision,left(p_reason,1000),v_source_version,v_delegator);
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'executive.approval.'||p_decision,a.entity_type,a.entity_id::text,
  jsonb_build_object('tenant_id',p_tenant_id,'approval_id',a.id,'source_version',v_source_version,'delegated_by',v_delegator,'reason',left(p_reason,1000)));
 return jsonb_build_object('approval_id',a.id,'decision',p_decision,'source_version',v_source_version,'version',a.version);
end $$;

create or replace function public.list_approval_decision_history(
 p_actor_user_id uuid,p_tenant_id uuid,p_branch_ids uuid[],p_approval_id uuid
) returns jsonb language plpgsql security definer set search_path=''
as $$
declare a public.executive_approval_requests%rowtype;v_role text;v_rows jsonb;
begin
 if coalesce(current_setting('request.jwt.claim.role',true),'')<>'service_role' then raise exception using errcode='42501',message='APPROVAL_SERVICE_ROLE_REQUIRED';end if;
 select role into v_role from public.tenant_memberships where tenant_id=p_tenant_id and user_id=p_actor_user_id and status='active';
 select * into a from public.executive_approval_requests where id=p_approval_id and tenant_id=p_tenant_id;
 if v_role is null or not found or (a.branch_id is not null and not a.branch_id=any(coalesce(p_branch_ids,'{}'::uuid[]))) then raise exception using errcode='42501',message='APPROVAL_HISTORY_SCOPE_DENIED';end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',d.id,'decision',d.decision,'reason',d.reason,'actor_user_id',d.actor_user_id,
  'source_version',d.source_version,'delegated_by',d.delegated_by,'created_at',d.created_at) order by d.created_at),'[]'::jsonb)
 into v_rows from public.executive_approval_decisions d where d.tenant_id=p_tenant_id and d.approval_id=p_approval_id;
 return v_rows;
end $$;

create or replace function public.create_approval_delegation(
 p_actor_user_id uuid,p_tenant_id uuid,p_branch_ids uuid[],p_delegate_user_id uuid,p_category text,p_branch_id uuid,p_starts_at timestamptz,p_ends_at timestamptz
) returns jsonb language plpgsql security definer set search_path=''
as $ declare v_role text;v_id uuid;begin
 if coalesce(current_setting('request.jwt.claim.role',true),'')<>'service_role' then raise exception using errcode='42501',message='APPROVAL_SERVICE_ROLE_REQUIRED';end if;
 if p_category not in ('procurement','finance','hr','branch_ops') or p_ends_at<=p_starts_at or p_ends_at<=now() or p_ends_at-p_starts_at>interval '30 days' then
  raise exception using errcode='22023',message='APPROVAL_DELEGATION_INPUT_INVALID';end if;
 select role into v_role from public.tenant_memberships where tenant_id=p_tenant_id and user_id=p_actor_user_id and status='active';
 if v_role is null or not exists(select 1 from public.executive_approval_policies p where p.tenant_id=p_tenant_id and p.category=p_category and p.enabled and v_role=any(p.required_roles)) then
  raise exception using errcode='42501',message='APPROVAL_DELEGATOR_ROLE_DENIED';end if;
 if (p_branch_id is not null and not (p_branch_id=any(coalesce(p_branch_ids,'{}'::uuid[])))) or (p_branch_id is null and v_role<>'tenant_owner') then raise exception using errcode='42501',message='APPROVAL_DELEGATION_BRANCH_DENIED';end if;
 if not exists(select 1 from public.tenant_memberships where tenant_id=p_tenant_id and user_id=p_delegate_user_id and status='active') then raise exception using errcode='42501',message='APPROVAL_DELEGATE_NOT_MEMBER';end if;
 insert into public.executive_approval_delegations(tenant_id,delegator_user_id,delegate_user_id,category,branch_id,starts_at,ends_at)
 values(p_tenant_id,p_actor_user_id,p_delegate_user_id,p_category,p_branch_id,p_starts_at,p_ends_at) returning id into v_id;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'executive.approval.delegation.created','executive_approval_delegations',v_id::text,
  jsonb_build_object('tenant_id',p_tenant_id,'delegate_user_id',p_delegate_user_id,'category',p_category,'branch_id',p_branch_id,'starts_at',p_starts_at,'ends_at',p_ends_at));
 return jsonb_build_object('delegation_id',v_id,'status','awaiting_owner_approval');
end $;

create or replace function public.approve_approval_delegation(
 p_actor_user_id uuid,p_tenant_id uuid,p_branch_ids uuid[],p_delegation_id uuid
) returns jsonb language plpgsql security definer set search_path=''
as $ declare v_role text;v_row public.executive_approval_delegations%rowtype;begin
 if coalesce(current_setting('request.jwt.claim.role',true),'')<>'service_role' then raise exception using errcode='42501',message='APPROVAL_SERVICE_ROLE_REQUIRED';end if;
 select role into v_role from public.tenant_memberships where tenant_id=p_tenant_id and user_id=p_actor_user_id and status='active';
 if v_role<>'tenant_owner' then raise exception using errcode='42501',message='APPROVAL_DELEGATION_OWNER_REQUIRED';end if;
 select * into v_row from public.executive_approval_delegations where id=p_delegation_id and tenant_id=p_tenant_id for update;
 if not found or v_row.revoked_at is not null or v_row.ends_at<=now() then raise exception using errcode='P0002',message='APPROVAL_DELEGATION_NOT_ACTIVE';end if;
 if v_row.delegator_user_id=p_actor_user_id then raise exception using errcode='42501',message='APPROVAL_DELEGATION_SELF_APPROVAL_DENIED';end if;
 if v_row.branch_id is not null and not (v_row.branch_id=any(coalesce(p_branch_ids,'{}'::uuid[]))) then raise exception using errcode='42501',message='APPROVAL_DELEGATION_BRANCH_DENIED';end if;
 update public.executive_approval_delegations set approved_by=p_actor_user_id,approved_at=now() where id=p_delegation_id returning * into v_row;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'executive.approval.delegation.approved','executive_approval_delegations',v_row.id::text,jsonb_build_object('tenant_id',p_tenant_id,'delegator_user_id',v_row.delegator_user_id,'delegate_user_id',v_row.delegate_user_id));
 return jsonb_build_object('delegation_id',v_row.id,'status','approved');
end $;

create or replace function public.revoke_approval_delegation(
 p_actor_user_id uuid,p_tenant_id uuid,p_delegation_id uuid
) returns jsonb language plpgsql security definer set search_path=''
as $ declare v_role text;v_row public.executive_approval_delegations%rowtype;begin
 if coalesce(current_setting('request.jwt.claim.role',true),'')<>'service_role' then raise exception using errcode='42501',message='APPROVAL_SERVICE_ROLE_REQUIRED';end if;
 select role into v_role from public.tenant_memberships where tenant_id=p_tenant_id and user_id=p_actor_user_id and status='active';
 select * into v_row from public.executive_approval_delegations where id=p_delegation_id and tenant_id=p_tenant_id for update;
 if not found or (v_row.delegator_user_id<>p_actor_user_id and v_role<>'tenant_owner') then raise exception using errcode='42501',message='APPROVAL_DELEGATION_REVOKE_DENIED';end if;
 update public.executive_approval_delegations set revoked_at=now() where id=p_delegation_id and revoked_at is null;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'executive.approval.delegation.revoked','executive_approval_delegations',v_row.id::text,jsonb_build_object('tenant_id',p_tenant_id));
 return jsonb_build_object('delegation_id',v_row.id,'status','revoked');
end $;

create or replace function public.list_approval_delegations(
 p_actor_user_id uuid,p_tenant_id uuid,p_branch_ids uuid[]
) returns jsonb language plpgsql security definer set search_path=''
as $ declare v_role text;v_rows jsonb;begin
 if coalesce(current_setting('request.jwt.claim.role',true),'')<>'service_role' then raise exception using errcode='42501',message='APPROVAL_SERVICE_ROLE_REQUIRED';end if;
 select role into v_role from public.tenant_memberships where tenant_id=p_tenant_id and user_id=p_actor_user_id and status='active';
 if v_role is null then raise exception using errcode='42501',message='APPROVAL_TENANT_MEMBERSHIP_REQUIRED';end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',d.id,'delegator_user_id',d.delegator_user_id,'delegate_user_id',d.delegate_user_id,
  'category',d.category,'branch_id',d.branch_id,'starts_at',d.starts_at,'ends_at',d.ends_at,'approved_by',d.approved_by,
  'approved_at',d.approved_at,'revoked_at',d.revoked_at,'created_at',d.created_at) order by d.created_at desc),'[]'::jsonb)
 into v_rows from public.executive_approval_delegations d where d.tenant_id=p_tenant_id
 and (v_role='tenant_owner' or d.delegator_user_id=p_actor_user_id or d.delegate_user_id=p_actor_user_id)
 and (d.branch_id is null and v_role='tenant_owner' or d.branch_id=any(coalesce(p_branch_ids,'{}'::uuid[])));
 return jsonb_build_object('delegations',v_rows);
end $;

revoke all on function public.enqueue_executive_approval(uuid,text,text,uuid,uuid,uuid,bigint,text) from public,anon,authenticated;
revoke all on function public.list_pending_approvals(uuid,uuid,uuid[],text[]) from public,anon,authenticated;
revoke all on function public.claim_approval(uuid,uuid,uuid[],uuid,integer) from public,anon,authenticated;
revoke all on function public.decide_approval(uuid,uuid,uuid[],uuid,text,text,integer) from public,anon,authenticated;
revoke all on function public.list_approval_decision_history(uuid,uuid,uuid[],uuid) from public,anon,authenticated;
grant execute on function public.list_pending_approvals(uuid,uuid,uuid[],text[]) to service_role;
grant execute on function public.claim_approval(uuid,uuid,uuid[],uuid,integer) to service_role;
grant execute on function public.decide_approval(uuid,uuid,uuid[],uuid,text,text,integer) to service_role;
grant execute on function public.list_approval_decision_history(uuid,uuid,uuid[],uuid) to service_role;
revoke all on function public.list_approval_delegations(uuid,uuid,uuid[]) from public,anon,authenticated;\ngrant execute on function public.list_approval_delegations(uuid,uuid,uuid[]) to service_role;\nrevoke all on function public.create_approval_delegation(uuid,uuid,uuid[],uuid,text,uuid,timestamptz,timestamptz) from public,anon,authenticated;
revoke all on function public.approve_approval_delegation(uuid,uuid,uuid[],uuid) from public,anon,authenticated;
revoke all on function public.revoke_approval_delegation(uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.create_approval_delegation(uuid,uuid,uuid[],uuid,text,uuid,timestamptz,timestamptz) to service_role;
grant execute on function public.approve_approval_delegation(uuid,uuid,uuid[],uuid) to service_role;
grant execute on function public.revoke_approval_delegation(uuid,uuid,uuid) to service_role;
commit;

  then (select (permissions->>'approval_limit_idr')::bigint from public.tenant_memberships where tenant_id=p_tenant_id and user_id=coalesce(v_delegator,p_actor_user_id))
  else 0 end;
 if a.amount_idr>v_limit then raise exception using errcode='42501',message='APPROVAL_AMOUNT_LIMIT';end if;
 if a.status='claimed' and a.claimed_by<>p_actor_user_id and a.claim_expires_at>now() then raise exception using errcode='55P03',message='APPROVAL_CLAIMED_BY_OTHER';end if;
 update public.executive_approval_requests set status='claimed',claimed_by=p_actor_user_id,claimed_at=now(),
  claim_expires_at=least(expires_at,now()+interval '5 minutes'),version=version+1,updated_at=now()
 where id=a.id returning * into a;
 return jsonb_build_object('approval_id',a.id,'claimed_by',a.claimed_by,'claim_expires_at',a.claim_expires_at,'version',a.version,'delegated_by',v_delegator);
end $$;

create or replace function public.decide_approval(
 p_actor_user_id uuid,p_tenant_id uuid,p_branch_ids uuid[],p_approval_id uuid,p_decision text,p_reason text,p_expected_version integer
) returns jsonb language plpgsql security definer set search_path=''
as $$
declare a public.executive_approval_requests%rowtype;v_role text;v_delegator uuid;v_limit bigint;v_updated integer:=0;v_source_version integer;
begin
 if coalesce(current_setting('request.jwt.claim.role',true),'')<>'service_role' then raise exception using errcode='42501',message='APPROVAL_SERVICE_ROLE_REQUIRED';end if;
 if p_decision not in ('approve','reject') or length(btrim(coalesce(p_reason,'')))<8 then raise exception using errcode='22023',message='APPROVAL_DECISION_INPUT_INVALID';end if;
 select role into v_role from public.tenant_memberships where tenant_id=p_tenant_id and user_id=p_actor_user_id and status='active';
 if v_role is null then raise exception using errcode='42501',message='APPROVAL_TENANT_MEMBERSHIP_REQUIRED';end if;
 select * into a from public.executive_approval_requests where id=p_approval_id and tenant_id=p_tenant_id for update;
 if not found then raise exception using errcode='P0002',message='APPROVAL_NOT_FOUND';end if;
 if a.branch_id is not null and not (a.branch_id=any(coalesce(p_branch_ids,'{}'::uuid[]))) then raise exception using errcode='42501',message='APPROVAL_BRANCH_SCOPE_DENIED';end if;
 if a.version<>p_expected_version then raise exception using errcode='40001',message='APPROVAL_STALE_VERSION';end if;
 if a.status not in ('pending','claimed') or a.expires_at<=now() then raise exception using errcode='55000',message='APPROVAL_NOT_PENDING_OR_EXPIRED';end if;
 if a.created_by=p_actor_user_id and not a.allow_self_approval then raise exception using errcode='42501',message='APPROVAL_SELF_APPROVAL_DENIED';end if;
 if not (v_role=any(a.required_roles)) then
  select d.delegator_user_id into v_delegator from public.executive_approval_delegations d join public.tenant_memberships dm
   on dm.tenant_id=d.tenant_id and dm.user_id=d.delegator_user_id and dm.status='active'
  where d.tenant_id=p_tenant_id and d.delegate_user_id=p_actor_user_id and d.category=a.category
   and (d.branch_id is null or d.branch_id is not distinct from a.branch_id)
   and d.approved_at is not null and d.revoked_at is null and now() between d.starts_at and d.ends_at
   and dm.role=any(a.required_roles) limit 1;
  if v_delegator is null then raise exception using errcode='42501',message='APPROVAL_ROLE_OR_DELEGATION_REQUIRED';end if;
 end if;
 v_limit:=case when v_role='owner' then 9223372036854775807
  when coalesce((select permissions->>'approval_limit_idr' from public.tenant_memberships where tenant_id=p_tenant_id and user_id=p_actor_user_id),'') ~ '^[0-9]+$'
  then (select (permissions->>'approval_limit_idr')::bigint from public.tenant_memberships where tenant_id=p_tenant_id and user_id=p_actor_user_id)
  else 0 end;
 if a.amount_idr>v_limit then raise exception using errcode='42501',message='APPROVAL_AMOUNT_LIMIT';end if;
 if a.status='claimed' and a.claimed_by<>p_actor_user_id and a.claim_expires_at>now() then raise exception using errcode='55P03',message='APPROVAL_CLAIMED_BY_OTHER';end if;

 if a.entity_type='purchase_requisition' then
  update public.purchase_requisitions set status=case when p_decision='approve' then 'approved' else 'rejected' end,
   approved_by=case when p_decision='approve' then p_actor_user_id else approved_by end,
   approved_at=case when p_decision='approve' then now() else approved_at end,
   rejected_by=case when p_decision='reject' then p_actor_user_id else rejected_by end,
   rejected_at=case when p_decision='reject' then now() else rejected_at end,updated_at=now()
  where id=a.entity_id and status='submitted';
 elsif a.entity_type='refund_record' then
  update public.refund_records set status=case when p_decision='approve' then 'approved' else 'rejected' end,
   reviewed_by=p_actor_user_id,reviewed_at=now()
  where id=a.entity_id and status='requested';
 elsif a.entity_type='hr_payroll_run' then
  update public.hr_payroll_runs set status=case when p_decision='approve' then 'approved' else 'cancelled' end,
   approved_by=case when p_decision='approve' then p_actor_user_id else approved_by end,
   approved_at=case when p_decision='approve' then now() else approved_at end,updated_at=now()
  where id=a.entity_id and tenant_id=p_tenant_id and status='submitted' and created_by<>p_actor_user_id;
 elsif a.entity_type='branch_ops_compliance_check' then
  update public.branch_ops_compliance_checks set status=case when p_decision='approve' then 'approved' else 'rejected' end,
   approved_by=case when p_decision='approve' then p_actor_user_id else approved_by end,
   approved_at=case when p_decision='approve' then now() else approved_at end,updated_at=now()
  where id=a.entity_id and tenant_id=p_tenant_id and status='submitted' and created_by<>p_actor_user_id;
 else raise exception using errcode='22023',message='APPROVAL_SOURCE_TYPE_UNSUPPORTED';
 end if;
 get diagnostics v_updated=row_count;
 if v_updated<>1 then raise exception using errcode='40001',message='APPROVAL_SOURCE_STALE_OR_ALREADY_CHANGED';end if;
 v_source_version:=a.source_version+1;
 update public.executive_approval_requests set status=case when p_decision='approve' then 'approved' else 'rejected' end,
  decided_by=p_actor_user_id,decided_at=now(),decision_reason=left(p_reason,1000),source_version=v_source_version,
  version=version+1,updated_at=now() where id=a.id returning version into a.version;
 insert into public.executive_approval_decisions(tenant_id,approval_id,actor_user_id,decision,reason,source_version,delegated_by)
 values(p_tenant_id,a.id,p_actor_user_id,p_decision,left(p_reason,1000),v_source_version,v_delegator);
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'executive.approval.'||p_decision,a.entity_type,a.entity_id::text,
  jsonb_build_object('tenant_id',p_tenant_id,'approval_id',a.id,'source_version',v_source_version,'delegated_by',v_delegator,'reason',left(p_reason,1000)));
 return jsonb_build_object('approval_id',a.id,'decision',p_decision,'source_version',v_source_version,'version',a.version);
end $$;

create or replace function public.list_approval_decision_history(
 p_actor_user_id uuid,p_tenant_id uuid,p_branch_ids uuid[],p_approval_id uuid
) returns jsonb language plpgsql security definer set search_path=''
as $$
declare a public.executive_approval_requests%rowtype;v_role text;v_rows jsonb;
begin
 if coalesce(current_setting('request.jwt.claim.role',true),'')<>'service_role' then raise exception using errcode='42501',message='APPROVAL_SERVICE_ROLE_REQUIRED';end if;
 select role into v_role from public.tenant_memberships where tenant_id=p_tenant_id and user_id=p_actor_user_id and status='active';
 select * into a from public.executive_approval_requests where id=p_approval_id and tenant_id=p_tenant_id;
 if v_role is null or not found or (a.branch_id is not null and not a.branch_id=any(coalesce(p_branch_ids,'{}'::uuid[]))) then raise exception using errcode='42501',message='APPROVAL_HISTORY_SCOPE_DENIED';end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',d.id,'decision',d.decision,'reason',d.reason,'actor_user_id',d.actor_user_id,
  'source_version',d.source_version,'delegated_by',d.delegated_by,'created_at',d.created_at) order by d.created_at),'[]'::jsonb)
 into v_rows from public.executive_approval_decisions d where d.tenant_id=p_tenant_id and d.approval_id=p_approval_id;
 return v_rows;
end $$;

create or replace function public.create_approval_delegation(
 p_actor_user_id uuid,p_tenant_id uuid,p_branch_ids uuid[],p_delegate_user_id uuid,p_category text,p_branch_id uuid,p_starts_at timestamptz,p_ends_at timestamptz
) returns jsonb language plpgsql security definer set search_path=''
as $ declare v_role text;v_id uuid;begin
 if coalesce(current_setting('request.jwt.claim.role',true),'')<>'service_role' then raise exception using errcode='42501',message='APPROVAL_SERVICE_ROLE_REQUIRED';end if;
 if p_category not in ('procurement','finance','hr','branch_ops') or p_ends_at<=p_starts_at or p_ends_at<=now() or p_ends_at-p_starts_at>interval '30 days' then
  raise exception using errcode='22023',message='APPROVAL_DELEGATION_INPUT_INVALID';end if;
 select role into v_role from public.tenant_memberships where tenant_id=p_tenant_id and user_id=p_actor_user_id and status='active';
 if v_role is null or not exists(select 1 from public.executive_approval_policies p where p.tenant_id=p_tenant_id and p.category=p_category and p.enabled and v_role=any(p.required_roles)) then
  raise exception using errcode='42501',message='APPROVAL_DELEGATOR_ROLE_DENIED';end if;
 if p_branch_id is not null and not (p_branch_id=any(coalesce(p_branch_ids,'{}'::uuid[]))) then raise exception using errcode='42501',message='APPROVAL_DELEGATION_BRANCH_DENIED';end if;
 if not exists(select 1 from public.tenant_memberships where tenant_id=p_tenant_id and user_id=p_delegate_user_id and status='active') then raise exception using errcode='42501',message='APPROVAL_DELEGATE_NOT_MEMBER';end if;
 insert into public.executive_approval_delegations(tenant_id,delegator_user_id,delegate_user_id,category,branch_id,starts_at,ends_at)
 values(p_tenant_id,p_actor_user_id,p_delegate_user_id,p_category,p_branch_id,p_starts_at,p_ends_at) returning id into v_id;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'executive.approval.delegation.created','executive_approval_delegations',v_id::text,
  jsonb_build_object('tenant_id',p_tenant_id,'delegate_user_id',p_delegate_user_id,'category',p_category,'branch_id',p_branch_id,'starts_at',p_starts_at,'ends_at',p_ends_at));
 return jsonb_build_object('delegation_id',v_id,'status','awaiting_owner_approval');
end $;

create or replace function public.approve_approval_delegation(
 p_actor_user_id uuid,p_tenant_id uuid,p_branch_ids uuid[],p_delegation_id uuid
) returns jsonb language plpgsql security definer set search_path=''
as $ declare v_role text;v_row public.executive_approval_delegations%rowtype;begin
 if coalesce(current_setting('request.jwt.claim.role',true),'')<>'service_role' then raise exception using errcode='42501',message='APPROVAL_SERVICE_ROLE_REQUIRED';end if;
 select role into v_role from public.tenant_memberships where tenant_id=p_tenant_id and user_id=p_actor_user_id and status='active';
 if v_role<>'tenant_owner' then raise exception using errcode='42501',message='APPROVAL_DELEGATION_OWNER_REQUIRED';end if;
 select * into v_row from public.executive_approval_delegations where id=p_delegation_id and tenant_id=p_tenant_id for update;
 if not found or v_row.revoked_at is not null or v_row.ends_at<=now() then raise exception using errcode='P0002',message='APPROVAL_DELEGATION_NOT_ACTIVE';end if;
 if v_row.branch_id is not null and not (v_row.branch_id=any(coalesce(p_branch_ids,'{}'::uuid[]))) then raise exception using errcode='42501',message='APPROVAL_DELEGATION_BRANCH_DENIED';end if;
 update public.executive_approval_delegations set approved_by=p_actor_user_id,approved_at=now() where id=p_delegation_id returning * into v_row;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'executive.approval.delegation.approved','executive_approval_delegations',v_row.id::text,jsonb_build_object('tenant_id',p_tenant_id,'delegator_user_id',v_row.delegator_user_id,'delegate_user_id',v_row.delegate_user_id));
 return jsonb_build_object('delegation_id',v_row.id,'status','approved');
end $;

create or replace function public.revoke_approval_delegation(
 p_actor_user_id uuid,p_tenant_id uuid,p_delegation_id uuid
) returns jsonb language plpgsql security definer set search_path=''
as $ declare v_role text;v_row public.executive_approval_delegations%rowtype;begin
 if coalesce(current_setting('request.jwt.claim.role',true),'')<>'service_role' then raise exception using errcode='42501',message='APPROVAL_SERVICE_ROLE_REQUIRED';end if;
 select role into v_role from public.tenant_memberships where tenant_id=p_tenant_id and user_id=p_actor_user_id and status='active';
 select * into v_row from public.executive_approval_delegations where id=p_delegation_id and tenant_id=p_tenant_id for update;
 if not found or (v_row.delegator_user_id<>p_actor_user_id and v_role<>'tenant_owner') then raise exception using errcode='42501',message='APPROVAL_DELEGATION_REVOKE_DENIED';end if;
 update public.executive_approval_delegations set revoked_at=now() where id=p_delegation_id and revoked_at is null;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'executive.approval.delegation.revoked','executive_approval_delegations',v_row.id::text,jsonb_build_object('tenant_id',p_tenant_id));
 return jsonb_build_object('delegation_id',v_row.id,'status','revoked');
end $;

revoke all on function public.enqueue_executive_approval(uuid,text,text,uuid,uuid,uuid,bigint,text) from public,anon,authenticated;
revoke all on function public.list_pending_approvals(uuid,uuid,uuid[],text[]) from public,anon,authenticated;
revoke all on function public.claim_approval(uuid,uuid,uuid[],uuid,integer) from public,anon,authenticated;
revoke all on function public.decide_approval(uuid,uuid,uuid[],uuid,text,text,integer) from public,anon,authenticated;
revoke all on function public.list_approval_decision_history(uuid,uuid,uuid[],uuid) from public,anon,authenticated;
grant execute on function public.list_pending_approvals(uuid,uuid,uuid[],text[]) to service_role;
grant execute on function public.claim_approval(uuid,uuid,uuid[],uuid,integer) to service_role;
grant execute on function public.decide_approval(uuid,uuid,uuid[],uuid,text,text,integer) to service_role;
grant execute on function public.list_approval_decision_history(uuid,uuid,uuid[],uuid) to service_role;
revoke all on function public.create_approval_delegation(uuid,uuid,uuid[],uuid,text,uuid,timestamptz,timestamptz) from public,anon,authenticated;
revoke all on function public.approve_approval_delegation(uuid,uuid,uuid[],uuid) from public,anon,authenticated;
revoke all on function public.revoke_approval_delegation(uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.create_approval_delegation(uuid,uuid,uuid[],uuid,text,uuid,timestamptz,timestamptz) to service_role;
grant execute on function public.approve_approval_delegation(uuid,uuid,uuid[],uuid) to service_role;
grant execute on function public.revoke_approval_delegation(uuid,uuid,uuid) to service_role;
commit;

  then (select (permissions->>'approval_limit_idr')::bigint from public.tenant_memberships where tenant_id=p_tenant_id and user_id=coalesce(v_delegator,p_actor_user_id))
  else 0 end;
 if a.amount_idr>v_limit then raise exception using errcode='42501',message='APPROVAL_AMOUNT_LIMIT';end if;
 if a.status='claimed' and a.claimed_by<>p_actor_user_id and a.claim_expires_at>now() then raise exception using errcode='55P03',message='APPROVAL_CLAIMED_BY_OTHER';end if;

 if a.entity_type='purchase_requisition' then
  update public.purchase_requisitions set status=case when p_decision='approve' then 'approved' else 'rejected' end,
   approved_by=case when p_decision='approve' then p_actor_user_id else approved_by end,
   approved_at=case when p_decision='approve' then now() else approved_at end,
   rejected_by=case when p_decision='reject' then p_actor_user_id else rejected_by end,
   rejected_at=case when p_decision='reject' then now() else rejected_at end,updated_at=now()
  where id=a.entity_id and status='submitted';
 elsif a.entity_type='refund_record' then
  update public.refund_records set status=case when p_decision='approve' then 'approved' else 'rejected' end,
   reviewed_by=p_actor_user_id,reviewed_at=now()
  where id=a.entity_id and status='requested';
 elsif a.entity_type='hr_payroll_run' then
  update public.hr_payroll_runs set status=case when p_decision='approve' then 'approved' else 'cancelled' end,
   approved_by=case when p_decision='approve' then p_actor_user_id else approved_by end,
   approved_at=case when p_decision='approve' then now() else approved_at end,updated_at=now()
  where id=a.entity_id and tenant_id=p_tenant_id and status='submitted' and created_by<>p_actor_user_id;
 elsif a.entity_type='branch_ops_compliance_check' then
  update public.branch_ops_compliance_checks set status=case when p_decision='approve' then 'approved' else 'rejected' end,
   approved_by=case when p_decision='approve' then p_actor_user_id else approved_by end,
   approved_at=case when p_decision='approve' then now() else approved_at end,updated_at=now()
  where id=a.entity_id and tenant_id=p_tenant_id and status='submitted' and created_by<>p_actor_user_id;
 else raise exception using errcode='22023',message='APPROVAL_SOURCE_TYPE_UNSUPPORTED';
 end if;
 get diagnostics v_updated=row_count;
 if v_updated<>1 then raise exception using errcode='40001',message='APPROVAL_SOURCE_STALE_OR_ALREADY_CHANGED';end if;
 v_source_version:=a.source_version+1;
 update public.executive_approval_requests set status=case when p_decision='approve' then 'approved' else 'rejected' end,
  decided_by=p_actor_user_id,decided_at=now(),decision_reason=left(p_reason,1000),source_version=v_source_version,
  version=version+1,updated_at=now() where id=a.id returning version into a.version;
 insert into public.executive_approval_decisions(tenant_id,approval_id,actor_user_id,decision,reason,source_version,delegated_by)
 values(p_tenant_id,a.id,p_actor_user_id,p_decision,left(p_reason,1000),v_source_version,v_delegator);
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'executive.approval.'||p_decision,a.entity_type,a.entity_id::text,
  jsonb_build_object('tenant_id',p_tenant_id,'approval_id',a.id,'source_version',v_source_version,'delegated_by',v_delegator,'reason',left(p_reason,1000)));
 return jsonb_build_object('approval_id',a.id,'decision',p_decision,'source_version',v_source_version,'version',a.version);
end $$;

create or replace function public.list_approval_decision_history(
 p_actor_user_id uuid,p_tenant_id uuid,p_branch_ids uuid[],p_approval_id uuid
) returns jsonb language plpgsql security definer set search_path=''
as $$
declare a public.executive_approval_requests%rowtype;v_role text;v_rows jsonb;
begin
 if coalesce(current_setting('request.jwt.claim.role',true),'')<>'service_role' then raise exception using errcode='42501',message='APPROVAL_SERVICE_ROLE_REQUIRED';end if;
 select role into v_role from public.tenant_memberships where tenant_id=p_tenant_id and user_id=p_actor_user_id and status='active';
 select * into a from public.executive_approval_requests where id=p_approval_id and tenant_id=p_tenant_id;
 if v_role is null or not found or (a.branch_id is not null and not a.branch_id=any(coalesce(p_branch_ids,'{}'::uuid[]))) then raise exception using errcode='42501',message='APPROVAL_HISTORY_SCOPE_DENIED';end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',d.id,'decision',d.decision,'reason',d.reason,'actor_user_id',d.actor_user_id,
  'source_version',d.source_version,'delegated_by',d.delegated_by,'created_at',d.created_at) order by d.created_at),'[]'::jsonb)
 into v_rows from public.executive_approval_decisions d where d.tenant_id=p_tenant_id and d.approval_id=p_approval_id;
 return v_rows;
end $$;

create or replace function public.create_approval_delegation(
 p_actor_user_id uuid,p_tenant_id uuid,p_branch_ids uuid[],p_delegate_user_id uuid,p_category text,p_branch_id uuid,p_starts_at timestamptz,p_ends_at timestamptz
) returns jsonb language plpgsql security definer set search_path=''
as $ declare v_role text;v_id uuid;begin
 if coalesce(current_setting('request.jwt.claim.role',true),'')<>'service_role' then raise exception using errcode='42501',message='APPROVAL_SERVICE_ROLE_REQUIRED';end if;
 if p_category not in ('procurement','finance','hr','branch_ops') or p_ends_at<=p_starts_at or p_ends_at<=now() or p_ends_at-p_starts_at>interval '30 days' then
  raise exception using errcode='22023',message='APPROVAL_DELEGATION_INPUT_INVALID';end if;
 select role into v_role from public.tenant_memberships where tenant_id=p_tenant_id and user_id=p_actor_user_id and status='active';
 if v_role is null or not exists(select 1 from public.executive_approval_policies p where p.tenant_id=p_tenant_id and p.category=p_category and p.enabled and v_role=any(p.required_roles)) then
  raise exception using errcode='42501',message='APPROVAL_DELEGATOR_ROLE_DENIED';end if;
 if p_branch_id is not null and not (p_branch_id=any(coalesce(p_branch_ids,'{}'::uuid[]))) then raise exception using errcode='42501',message='APPROVAL_DELEGATION_BRANCH_DENIED';end if;
 if not exists(select 1 from public.tenant_memberships where tenant_id=p_tenant_id and user_id=p_delegate_user_id and status='active') then raise exception using errcode='42501',message='APPROVAL_DELEGATE_NOT_MEMBER';end if;
 insert into public.executive_approval_delegations(tenant_id,delegator_user_id,delegate_user_id,category,branch_id,starts_at,ends_at)
 values(p_tenant_id,p_actor_user_id,p_delegate_user_id,p_category,p_branch_id,p_starts_at,p_ends_at) returning id into v_id;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'executive.approval.delegation.created','executive_approval_delegations',v_id::text,
  jsonb_build_object('tenant_id',p_tenant_id,'delegate_user_id',p_delegate_user_id,'category',p_category,'branch_id',p_branch_id,'starts_at',p_starts_at,'ends_at',p_ends_at));
 return jsonb_build_object('delegation_id',v_id,'status','awaiting_owner_approval');
end $;

create or replace function public.approve_approval_delegation(
 p_actor_user_id uuid,p_tenant_id uuid,p_branch_ids uuid[],p_delegation_id uuid
) returns jsonb language plpgsql security definer set search_path=''
as $ declare v_role text;v_row public.executive_approval_delegations%rowtype;begin
 if coalesce(current_setting('request.jwt.claim.role',true),'')<>'service_role' then raise exception using errcode='42501',message='APPROVAL_SERVICE_ROLE_REQUIRED';end if;
 select role into v_role from public.tenant_memberships where tenant_id=p_tenant_id and user_id=p_actor_user_id and status='active';
 if v_role<>'tenant_owner' then raise exception using errcode='42501',message='APPROVAL_DELEGATION_OWNER_REQUIRED';end if;
 select * into v_row from public.executive_approval_delegations where id=p_delegation_id and tenant_id=p_tenant_id for update;
 if not found or v_row.revoked_at is not null or v_row.ends_at<=now() then raise exception using errcode='P0002',message='APPROVAL_DELEGATION_NOT_ACTIVE';end if;
 if v_row.delegator_user_id=p_actor_user_id then raise exception using errcode='42501',message='APPROVAL_DELEGATION_SELF_APPROVAL_DENIED';end if;
 if v_row.branch_id is not null and not (v_row.branch_id=any(coalesce(p_branch_ids,'{}'::uuid[]))) then raise exception using errcode='42501',message='APPROVAL_DELEGATION_BRANCH_DENIED';end if;
 update public.executive_approval_delegations set approved_by=p_actor_user_id,approved_at=now() where id=p_delegation_id returning * into v_row;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'executive.approval.delegation.approved','executive_approval_delegations',v_row.id::text,jsonb_build_object('tenant_id',p_tenant_id,'delegator_user_id',v_row.delegator_user_id,'delegate_user_id',v_row.delegate_user_id));
 return jsonb_build_object('delegation_id',v_row.id,'status','approved');
end $;

create or replace function public.revoke_approval_delegation(
 p_actor_user_id uuid,p_tenant_id uuid,p_delegation_id uuid
) returns jsonb language plpgsql security definer set search_path=''
as $ declare v_role text;v_row public.executive_approval_delegations%rowtype;begin
 if coalesce(current_setting('request.jwt.claim.role',true),'')<>'service_role' then raise exception using errcode='42501',message='APPROVAL_SERVICE_ROLE_REQUIRED';end if;
 select role into v_role from public.tenant_memberships where tenant_id=p_tenant_id and user_id=p_actor_user_id and status='active';
 select * into v_row from public.executive_approval_delegations where id=p_delegation_id and tenant_id=p_tenant_id for update;
 if not found or (v_row.delegator_user_id<>p_actor_user_id and v_role<>'tenant_owner') then raise exception using errcode='42501',message='APPROVAL_DELEGATION_REVOKE_DENIED';end if;
 update public.executive_approval_delegations set revoked_at=now() where id=p_delegation_id and revoked_at is null;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'executive.approval.delegation.revoked','executive_approval_delegations',v_row.id::text,jsonb_build_object('tenant_id',p_tenant_id));
 return jsonb_build_object('delegation_id',v_row.id,'status','revoked');
end $;

revoke all on function public.enqueue_executive_approval(uuid,text,text,uuid,uuid,uuid,bigint,text) from public,anon,authenticated;
revoke all on function public.list_pending_approvals(uuid,uuid,uuid[],text[]) from public,anon,authenticated;
revoke all on function public.claim_approval(uuid,uuid,uuid[],uuid,integer) from public,anon,authenticated;
revoke all on function public.decide_approval(uuid,uuid,uuid[],uuid,text,text,integer) from public,anon,authenticated;
revoke all on function public.list_approval_decision_history(uuid,uuid,uuid[],uuid) from public,anon,authenticated;
grant execute on function public.list_pending_approvals(uuid,uuid,uuid[],text[]) to service_role;
grant execute on function public.claim_approval(uuid,uuid,uuid[],uuid,integer) to service_role;
grant execute on function public.decide_approval(uuid,uuid,uuid[],uuid,text,text,integer) to service_role;
grant execute on function public.list_approval_decision_history(uuid,uuid,uuid[],uuid) to service_role;
revoke all on function public.create_approval_delegation(uuid,uuid,uuid[],uuid,text,uuid,timestamptz,timestamptz) from public,anon,authenticated;
revoke all on function public.approve_approval_delegation(uuid,uuid,uuid[],uuid) from public,anon,authenticated;
revoke all on function public.revoke_approval_delegation(uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.create_approval_delegation(uuid,uuid,uuid[],uuid,text,uuid,timestamptz,timestamptz) to service_role;
grant execute on function public.approve_approval_delegation(uuid,uuid,uuid[],uuid) to service_role;
grant execute on function public.revoke_approval_delegation(uuid,uuid,uuid) to service_role;
commit;

  then (select (permissions->>'approval_limit_idr')::bigint from public.tenant_memberships where tenant_id=p_tenant_id and user_id=coalesce(v_delegator,p_actor_user_id))
  else 0 end;
 if a.amount_idr>v_limit then raise exception using errcode='42501',message='APPROVAL_AMOUNT_LIMIT';end if;
 if a.status='claimed' and a.claimed_by<>p_actor_user_id and a.claim_expires_at>now() then raise exception using errcode='55P03',message='APPROVAL_CLAIMED_BY_OTHER';end if;
 update public.executive_approval_requests set status='claimed',claimed_by=p_actor_user_id,claimed_at=now(),
  claim_expires_at=least(expires_at,now()+interval '5 minutes'),version=version+1,updated_at=now()
 where id=a.id returning * into a;
 return jsonb_build_object('approval_id',a.id,'claimed_by',a.claimed_by,'claim_expires_at',a.claim_expires_at,'version',a.version,'delegated_by',v_delegator);
end $$;

create or replace function public.decide_approval(
 p_actor_user_id uuid,p_tenant_id uuid,p_branch_ids uuid[],p_approval_id uuid,p_decision text,p_reason text,p_expected_version integer
) returns jsonb language plpgsql security definer set search_path=''
as $$
declare a public.executive_approval_requests%rowtype;v_role text;v_delegator uuid;v_limit bigint;v_updated integer:=0;v_source_version integer;
begin
 if coalesce(current_setting('request.jwt.claim.role',true),'')<>'service_role' then raise exception using errcode='42501',message='APPROVAL_SERVICE_ROLE_REQUIRED';end if;
 if p_decision not in ('approve','reject') or length(btrim(coalesce(p_reason,'')))<8 then raise exception using errcode='22023',message='APPROVAL_DECISION_INPUT_INVALID';end if;
 select role into v_role from public.tenant_memberships where tenant_id=p_tenant_id and user_id=p_actor_user_id and status='active';
 if v_role is null then raise exception using errcode='42501',message='APPROVAL_TENANT_MEMBERSHIP_REQUIRED';end if;
 select * into a from public.executive_approval_requests where id=p_approval_id and tenant_id=p_tenant_id for update;
 if not found then raise exception using errcode='P0002',message='APPROVAL_NOT_FOUND';end if;
 if a.branch_id is not null and not (a.branch_id=any(coalesce(p_branch_ids,'{}'::uuid[]))) then raise exception using errcode='42501',message='APPROVAL_BRANCH_SCOPE_DENIED';end if;
 if a.version<>p_expected_version then raise exception using errcode='40001',message='APPROVAL_STALE_VERSION';end if;
 if a.status not in ('pending','claimed') or a.expires_at<=now() then raise exception using errcode='55000',message='APPROVAL_NOT_PENDING_OR_EXPIRED';end if;
 if a.created_by=p_actor_user_id and not a.allow_self_approval then raise exception using errcode='42501',message='APPROVAL_SELF_APPROVAL_DENIED';end if;
 if not (v_role=any(a.required_roles)) then
  select d.delegator_user_id into v_delegator from public.executive_approval_delegations d join public.tenant_memberships dm
   on dm.tenant_id=d.tenant_id and dm.user_id=d.delegator_user_id and dm.status='active'
  where d.tenant_id=p_tenant_id and d.delegate_user_id=p_actor_user_id and d.category=a.category
   and (d.branch_id is null or d.branch_id is not distinct from a.branch_id)
   and d.approved_at is not null and d.revoked_at is null and now() between d.starts_at and d.ends_at
   and dm.role=any(a.required_roles) limit 1;
  if v_delegator is null then raise exception using errcode='42501',message='APPROVAL_ROLE_OR_DELEGATION_REQUIRED';end if;
 end if;
 v_limit:=case when v_role='owner' then 9223372036854775807
  when coalesce((select permissions->>'approval_limit_idr' from public.tenant_memberships where tenant_id=p_tenant_id and user_id=p_actor_user_id),'') ~ '^[0-9]+$'
  then (select (permissions->>'approval_limit_idr')::bigint from public.tenant_memberships where tenant_id=p_tenant_id and user_id=p_actor_user_id)
  else 0 end;
 if a.amount_idr>v_limit then raise exception using errcode='42501',message='APPROVAL_AMOUNT_LIMIT';end if;
 if a.status='claimed' and a.claimed_by<>p_actor_user_id and a.claim_expires_at>now() then raise exception using errcode='55P03',message='APPROVAL_CLAIMED_BY_OTHER';end if;

 if a.entity_type='purchase_requisition' then
  update public.purchase_requisitions set status=case when p_decision='approve' then 'approved' else 'rejected' end,
   approved_by=case when p_decision='approve' then p_actor_user_id else approved_by end,
   approved_at=case when p_decision='approve' then now() else approved_at end,
   rejected_by=case when p_decision='reject' then p_actor_user_id else rejected_by end,
   rejected_at=case when p_decision='reject' then now() else rejected_at end,updated_at=now()
  where id=a.entity_id and status='submitted';
 elsif a.entity_type='refund_record' then
  update public.refund_records set status=case when p_decision='approve' then 'approved' else 'rejected' end,
   reviewed_by=p_actor_user_id,reviewed_at=now()
  where id=a.entity_id and status='requested';
 elsif a.entity_type='hr_payroll_run' then
  update public.hr_payroll_runs set status=case when p_decision='approve' then 'approved' else 'cancelled' end,
   approved_by=case when p_decision='approve' then p_actor_user_id else approved_by end,
   approved_at=case when p_decision='approve' then now() else approved_at end,updated_at=now()
  where id=a.entity_id and tenant_id=p_tenant_id and status='submitted' and created_by<>p_actor_user_id;
 elsif a.entity_type='branch_ops_compliance_check' then
  update public.branch_ops_compliance_checks set status=case when p_decision='approve' then 'approved' else 'rejected' end,
   approved_by=case when p_decision='approve' then p_actor_user_id else approved_by end,
   approved_at=case when p_decision='approve' then now() else approved_at end,updated_at=now()
  where id=a.entity_id and tenant_id=p_tenant_id and status='submitted' and created_by<>p_actor_user_id;
 else raise exception using errcode='22023',message='APPROVAL_SOURCE_TYPE_UNSUPPORTED';
 end if;
 get diagnostics v_updated=row_count;
 if v_updated<>1 then raise exception using errcode='40001',message='APPROVAL_SOURCE_STALE_OR_ALREADY_CHANGED';end if;
 v_source_version:=a.source_version+1;
 update public.executive_approval_requests set status=case when p_decision='approve' then 'approved' else 'rejected' end,
  decided_by=p_actor_user_id,decided_at=now(),decision_reason=left(p_reason,1000),source_version=v_source_version,
  version=version+1,updated_at=now() where id=a.id returning version into a.version;
 insert into public.executive_approval_decisions(tenant_id,approval_id,actor_user_id,decision,reason,source_version,delegated_by)
 values(p_tenant_id,a.id,p_actor_user_id,p_decision,left(p_reason,1000),v_source_version,v_delegator);
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'executive.approval.'||p_decision,a.entity_type,a.entity_id::text,
  jsonb_build_object('tenant_id',p_tenant_id,'approval_id',a.id,'source_version',v_source_version,'delegated_by',v_delegator,'reason',left(p_reason,1000)));
 return jsonb_build_object('approval_id',a.id,'decision',p_decision,'source_version',v_source_version,'version',a.version);
end $$;

create or replace function public.list_approval_decision_history(
 p_actor_user_id uuid,p_tenant_id uuid,p_branch_ids uuid[],p_approval_id uuid
) returns jsonb language plpgsql security definer set search_path=''
as $$
declare a public.executive_approval_requests%rowtype;v_role text;v_rows jsonb;
begin
 if coalesce(current_setting('request.jwt.claim.role',true),'')<>'service_role' then raise exception using errcode='42501',message='APPROVAL_SERVICE_ROLE_REQUIRED';end if;
 select role into v_role from public.tenant_memberships where tenant_id=p_tenant_id and user_id=p_actor_user_id and status='active';
 select * into a from public.executive_approval_requests where id=p_approval_id and tenant_id=p_tenant_id;
 if v_role is null or not found or (a.branch_id is not null and not a.branch_id=any(coalesce(p_branch_ids,'{}'::uuid[]))) then raise exception using errcode='42501',message='APPROVAL_HISTORY_SCOPE_DENIED';end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',d.id,'decision',d.decision,'reason',d.reason,'actor_user_id',d.actor_user_id,
  'source_version',d.source_version,'delegated_by',d.delegated_by,'created_at',d.created_at) order by d.created_at),'[]'::jsonb)
 into v_rows from public.executive_approval_decisions d where d.tenant_id=p_tenant_id and d.approval_id=p_approval_id;
 return v_rows;
end $$;

create or replace function public.create_approval_delegation(
 p_actor_user_id uuid,p_tenant_id uuid,p_branch_ids uuid[],p_delegate_user_id uuid,p_category text,p_branch_id uuid,p_starts_at timestamptz,p_ends_at timestamptz
) returns jsonb language plpgsql security definer set search_path=''
as $ declare v_role text;v_id uuid;begin
 if coalesce(current_setting('request.jwt.claim.role',true),'')<>'service_role' then raise exception using errcode='42501',message='APPROVAL_SERVICE_ROLE_REQUIRED';end if;
 if p_category not in ('procurement','finance','hr','branch_ops') or p_ends_at<=p_starts_at or p_ends_at<=now() or p_ends_at-p_starts_at>interval '30 days' then
  raise exception using errcode='22023',message='APPROVAL_DELEGATION_INPUT_INVALID';end if;
 select role into v_role from public.tenant_memberships where tenant_id=p_tenant_id and user_id=p_actor_user_id and status='active';
 if v_role is null or not exists(select 1 from public.executive_approval_policies p where p.tenant_id=p_tenant_id and p.category=p_category and p.enabled and v_role=any(p.required_roles)) then
  raise exception using errcode='42501',message='APPROVAL_DELEGATOR_ROLE_DENIED';end if;
 if p_branch_id is not null and not (p_branch_id=any(coalesce(p_branch_ids,'{}'::uuid[]))) then raise exception using errcode='42501',message='APPROVAL_DELEGATION_BRANCH_DENIED';end if;
 if not exists(select 1 from public.tenant_memberships where tenant_id=p_tenant_id and user_id=p_delegate_user_id and status='active') then raise exception using errcode='42501',message='APPROVAL_DELEGATE_NOT_MEMBER';end if;
 insert into public.executive_approval_delegations(tenant_id,delegator_user_id,delegate_user_id,category,branch_id,starts_at,ends_at)
 values(p_tenant_id,p_actor_user_id,p_delegate_user_id,p_category,p_branch_id,p_starts_at,p_ends_at) returning id into v_id;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'executive.approval.delegation.created','executive_approval_delegations',v_id::text,
  jsonb_build_object('tenant_id',p_tenant_id,'delegate_user_id',p_delegate_user_id,'category',p_category,'branch_id',p_branch_id,'starts_at',p_starts_at,'ends_at',p_ends_at));
 return jsonb_build_object('delegation_id',v_id,'status','awaiting_owner_approval');
end $;

create or replace function public.approve_approval_delegation(
 p_actor_user_id uuid,p_tenant_id uuid,p_branch_ids uuid[],p_delegation_id uuid
) returns jsonb language plpgsql security definer set search_path=''
as $ declare v_role text;v_row public.executive_approval_delegations%rowtype;begin
 if coalesce(current_setting('request.jwt.claim.role',true),'')<>'service_role' then raise exception using errcode='42501',message='APPROVAL_SERVICE_ROLE_REQUIRED';end if;
 select role into v_role from public.tenant_memberships where tenant_id=p_tenant_id and user_id=p_actor_user_id and status='active';
 if v_role<>'tenant_owner' then raise exception using errcode='42501',message='APPROVAL_DELEGATION_OWNER_REQUIRED';end if;
 select * into v_row from public.executive_approval_delegations where id=p_delegation_id and tenant_id=p_tenant_id for update;
 if not found or v_row.revoked_at is not null or v_row.ends_at<=now() then raise exception using errcode='P0002',message='APPROVAL_DELEGATION_NOT_ACTIVE';end if;
 if v_row.branch_id is not null and not (v_row.branch_id=any(coalesce(p_branch_ids,'{}'::uuid[]))) then raise exception using errcode='42501',message='APPROVAL_DELEGATION_BRANCH_DENIED';end if;
 update public.executive_approval_delegations set approved_by=p_actor_user_id,approved_at=now() where id=p_delegation_id returning * into v_row;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'executive.approval.delegation.approved','executive_approval_delegations',v_row.id::text,jsonb_build_object('tenant_id',p_tenant_id,'delegator_user_id',v_row.delegator_user_id,'delegate_user_id',v_row.delegate_user_id));
 return jsonb_build_object('delegation_id',v_row.id,'status','approved');
end $;

create or replace function public.revoke_approval_delegation(
 p_actor_user_id uuid,p_tenant_id uuid,p_delegation_id uuid
) returns jsonb language plpgsql security definer set search_path=''
as $ declare v_role text;v_row public.executive_approval_delegations%rowtype;begin
 if coalesce(current_setting('request.jwt.claim.role',true),'')<>'service_role' then raise exception using errcode='42501',message='APPROVAL_SERVICE_ROLE_REQUIRED';end if;
 select role into v_role from public.tenant_memberships where tenant_id=p_tenant_id and user_id=p_actor_user_id and status='active';
 select * into v_row from public.executive_approval_delegations where id=p_delegation_id and tenant_id=p_tenant_id for update;
 if not found or (v_row.delegator_user_id<>p_actor_user_id and v_role<>'tenant_owner') then raise exception using errcode='42501',message='APPROVAL_DELEGATION_REVOKE_DENIED';end if;
 update public.executive_approval_delegations set revoked_at=now() where id=p_delegation_id and revoked_at is null;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'executive.approval.delegation.revoked','executive_approval_delegations',v_row.id::text,jsonb_build_object('tenant_id',p_tenant_id));
 return jsonb_build_object('delegation_id',v_row.id,'status','revoked');
end $;

revoke all on function public.enqueue_executive_approval(uuid,text,text,uuid,uuid,uuid,bigint,text) from public,anon,authenticated;
revoke all on function public.list_pending_approvals(uuid,uuid,uuid[],text[]) from public,anon,authenticated;
revoke all on function public.claim_approval(uuid,uuid,uuid[],uuid,integer) from public,anon,authenticated;
revoke all on function public.decide_approval(uuid,uuid,uuid[],uuid,text,text,integer) from public,anon,authenticated;
revoke all on function public.list_approval_decision_history(uuid,uuid,uuid[],uuid) from public,anon,authenticated;
grant execute on function public.list_pending_approvals(uuid,uuid,uuid[],text[]) to service_role;
grant execute on function public.claim_approval(uuid,uuid,uuid[],uuid,integer) to service_role;
grant execute on function public.decide_approval(uuid,uuid,uuid[],uuid,text,text,integer) to service_role;
grant execute on function public.list_approval_decision_history(uuid,uuid,uuid[],uuid) to service_role;
revoke all on function public.create_approval_delegation(uuid,uuid,uuid[],uuid,text,uuid,timestamptz,timestamptz) from public,anon,authenticated;
revoke all on function public.approve_approval_delegation(uuid,uuid,uuid[],uuid) from public,anon,authenticated;
revoke all on function public.revoke_approval_delegation(uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.create_approval_delegation(uuid,uuid,uuid[],uuid,text,uuid,timestamptz,timestamptz) to service_role;
grant execute on function public.approve_approval_delegation(uuid,uuid,uuid[],uuid) to service_role;
grant execute on function public.revoke_approval_delegation(uuid,uuid,uuid) to service_role;
commit;
