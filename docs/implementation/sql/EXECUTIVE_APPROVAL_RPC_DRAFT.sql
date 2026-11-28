-- DESIGN DRAFT ONLY — NOT A MIGRATION.
-- Depends on EXECUTIVE_SALES_APPROVAL_DRAFT.sql.
-- This file defines a server-only approval inbox projection and source transition RPCs.
-- Do not apply until disposable replay and independent ACL review pass.
begin;

alter table public.executive_approval_policies
 add column if not exists branch_id uuid;
alter table public.executive_approval_inbox
 add column if not exists policy_id uuid,
 add column if not exists required_role text,
 add column if not exists version integer not null default 1;
do $$ begin
 if not exists(select 1 from pg_constraint where conname='executive_approval_policy_branch_fkey') then
  alter table public.executive_approval_policies add constraint executive_approval_policy_branch_fkey
   foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict;
 end if;
 if not exists(select 1 from pg_constraint where conname='executive_approval_inbox_policy_fkey') then
  alter table public.executive_approval_inbox add constraint executive_approval_inbox_policy_fkey
   foreign key(tenant_id,policy_id) references public.executive_approval_policies(tenant_id,id) on delete restrict;
 end if;
end $$;

alter table public.branch_operation_checklist_runs
 add column if not exists approval_status text not null default 'not_required',
 add column if not exists approved_by uuid references auth.users(id) on delete restrict,
 add column if not exists approved_at timestamptz,
 add column if not exists approval_reason text;
alter table public.branch_operation_checklist_runs
 drop constraint if exists branch_operation_checklist_approval_state_check;
alter table public.branch_operation_checklist_runs
 add constraint branch_operation_checklist_approval_state_check
 check(approval_status in ('not_required','pending','approved','rejected')
  and ((approval_status='approved' and approved_by is not null and approved_at is not null)
   or (approval_status<>'approved' and approved_at is null))
  and (approved_by is null or approved_by<>completed_by));

create or replace view public.executive_pending_approval_sources
with (security_invoker=true) as
select b.tenant_id,'procurement'::text source_domain,'purchase_requisition'::text source_entity,
 pr.id source_entity_id,pr.branch_id,'procurement'::text category,pr.estimated_total_idr amount_idr,
 pr.requested_by created_by,(extract(epoch from pr.updated_at)*1000)::bigint source_version,pr.updated_at source_updated_at
from public.purchase_requisitions pr join public.branches b on b.id=pr.branch_id where pr.status='submitted'
union all
select b.tenant_id,'procurement','purchase_order',po.id,po.branch_id,'procurement',po.subtotal_idr,po.requested_by,
 (extract(epoch from po.updated_at)*1000)::bigint,po.updated_at
from public.purchase_orders po join public.branches b on b.id=po.branch_id where po.status='submitted'
union all
select pr.tenant_id,'hr','hr_payroll_run',pr.id,pr.branch_id,'hr',pr.net_amount_idr,pr.created_by,
 (extract(epoch from pr.updated_at)*1000)::bigint,pr.updated_at
from public.hr_payroll_runs pr where pr.status='submitted'
union all
select fp.tenant_id,'finance','hr_payroll_finance_posting',fp.id,fp.branch_id,'finance',fp.net_amount_idr,fp.created_by,
 (extract(epoch from fp.updated_at)*1000)::bigint,fp.updated_at
from public.hr_payroll_finance_postings fp where fp.status='draft'
union all
select b.tenant_id,'branch_ops','branch_operation_checklist_run',cr.id,cr.branch_id,'branch_ops',0,cr.completed_by,
 cr.version::bigint,cr.updated_at
from public.branch_operation_checklist_runs cr join public.branches b on b.id=cr.branch_id
where cr.status='completed' and cr.approval_status='pending';
revoke all on public.executive_pending_approval_sources from public,anon,authenticated;
grant select on public.executive_pending_approval_sources to service_role;

create or replace function public.executive_approval_actor_has_role(
 p_actor_user_id uuid,p_tenant_id uuid,p_branch_id uuid,p_category text,p_required_role text
) returns boolean language sql security invoker set search_path=''
as $$
 select
  exists(select 1 from public.tenant_memberships tm where tm.tenant_id=p_tenant_id and tm.user_id=p_actor_user_id
   and tm.status='active' and tm.role=p_required_role)
  or exists(select 1 from public.branch_assignments ba join public.branches b on b.id=ba.branch_id
   join public.job_positions jp on jp.id=ba.job_position_id
   where b.tenant_id=p_tenant_id and ba.branch_id=p_branch_id and ba.user_id=p_actor_user_id
    and ba.employment_status='active' and ba.starts_on<=current_date
    and (ba.ends_on is null or ba.ends_on>=current_date) and jp.code=p_required_role)
  or exists(select 1 from public.executive_approval_delegations d
   where d.tenant_id=p_tenant_id and d.delegate_user_id=p_actor_user_id
    and d.category=p_category and (d.branch_id is null or d.branch_id=p_branch_id)
    and d.status='active' and d.starts_at<=now() and d.ends_at>now()
    and d.approved_by is not null and d.approved_by<>d.created_by
    and (exists(select 1 from public.tenant_memberships tm where tm.tenant_id=p_tenant_id
       and tm.user_id=d.delegator_user_id and tm.status='active' and tm.role=p_required_role)
      or exists(select 1 from public.branch_assignments ba join public.branches b on b.id=ba.branch_id
       join public.job_positions jp on jp.id=ba.job_position_id
       where b.tenant_id=p_tenant_id and ba.branch_id=p_branch_id and ba.user_id=d.delegator_user_id
        and ba.employment_status='active' and jp.code=p_required_role)));
$$;
revoke all on function public.executive_approval_actor_has_role(uuid,uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function public.executive_approval_actor_has_role(uuid,uuid,uuid,text,text) to service_role;

create or replace function public.list_pending_approvals(
 p_actor_user_id uuid,p_tenant_id uuid,p_branch_ids uuid[],p_categories text[]
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v_role text; v_allowed uuid[]; v_requested uuid[]; v_rows jsonb;
begin
 if coalesce(auth.jwt()->>'role','')<>'service_role' then raise exception using errcode='42501',message='EXECUTIVE_SERVICE_ROLE_REQUIRED'; end if;
 select role into v_role from public.tenant_memberships where tenant_id=p_tenant_id and user_id=p_actor_user_id and status='active';
 if not found then raise exception using errcode='42501',message='APPROVAL_TENANT_MEMBERSHIP_REQUIRED'; end if;
 if v_role in ('tenant_owner','tenant_admin','group_hq','head_ops') then
  select coalesce(array_agg(id),'{}'::uuid[]) into v_allowed from public.branches where tenant_id=p_tenant_id;
 else
  select coalesce(array_agg(distinct b.id),'{}'::uuid[]) into v_allowed from public.branches b
   join public.branch_assignments ba on ba.branch_id=b.id
   where b.tenant_id=p_tenant_id and ba.user_id=p_actor_user_id and ba.employment_status='active'
    and ba.starts_on<=current_date and (ba.ends_on is null or ba.ends_on>=current_date);
 end if;
 v_requested:=case when coalesce(cardinality(p_branch_ids),0)=0 then v_allowed else p_branch_ids end;
 if not(v_requested<@v_allowed) then raise exception using errcode='42501',message='APPROVAL_BRANCH_SCOPE_DENIED'; end if;
 insert into public.executive_approval_inbox(tenant_id,source_domain,source_entity,source_entity_id,branch_id,category,
  amount_idr,created_by,source_version,policy_id,required_role,expires_at)
 select distinct on(s.source_entity,s.source_entity_id) s.tenant_id,s.source_domain,s.source_entity,s.source_entity_id,s.branch_id,
  s.category,s.amount_idr,s.created_by,s.source_version,p.id,p.required_role,now()+make_interval(mins=>p.expiry_minutes)
 from public.executive_pending_approval_sources s
 join public.executive_approval_policies p on p.tenant_id=s.tenant_id and p.category=s.category
  and p.status='active' and (p.branch_id is null or p.branch_id=s.branch_id) and p.max_amount_idr>=s.amount_idr
 where s.tenant_id=p_tenant_id and s.branch_id=any(v_requested)
  and (p_categories is null or s.category=any(p_categories))
  and (s.created_by<>p_actor_user_id or p.self_approval_allowed)
  and public.executive_approval_actor_has_role(p_actor_user_id,p_tenant_id,s.branch_id,s.category,p.required_role)
 order by s.source_entity,s.source_entity_id,p.max_amount_idr asc
 on conflict(tenant_id,source_entity,source_entity_id) do update set
  source_version=excluded.source_version,policy_id=excluded.policy_id,required_role=excluded.required_role,
  amount_idr=excluded.amount_idr,expires_at=excluded.expires_at,updated_at=now(),
  status=case when executive_approval_inbox.status in ('pending','expired') then 'pending' else executive_approval_inbox.status end,
  claimed_by=case when executive_approval_inbox.source_version<>excluded.source_version then null else executive_approval_inbox.claimed_by end,
  claim_expires_at=case when executive_approval_inbox.source_version<>excluded.source_version then null else executive_approval_inbox.claim_expires_at end,
  version=case when executive_approval_inbox.source_version<>excluded.source_version then executive_approval_inbox.version+1 else executive_approval_inbox.version end;
 select coalesce(jsonb_agg(to_jsonb(i)||jsonb_build_object('branch_code',b.code,'branch_name',b.name)
  order by i.expires_at,i.amount_idr desc),'[]'::jsonb) into v_rows
 from public.executive_approval_inbox i join public.branches b on b.id=i.branch_id
 join public.executive_pending_approval_sources s on s.tenant_id=i.tenant_id
  and s.source_entity=i.source_entity and s.source_entity_id=i.source_entity_id and s.source_version=i.source_version
 where i.tenant_id=p_tenant_id and i.branch_id=any(v_requested) and i.status in ('pending','claimed')
  and i.expires_at>now() and (p_categories is null or i.category=any(p_categories))
  and (i.created_by<>p_actor_user_id or (select self_approval_allowed from public.executive_approval_policies where id=i.policy_id))
  and public.executive_approval_actor_has_role(p_actor_user_id,p_tenant_id,i.branch_id,i.category,i.required_role);
 return jsonb_build_object('approvals',v_rows);
end $$;
revoke all on function public.list_pending_approvals(uuid,uuid,uuid[],text[]) from public,anon,authenticated;
grant execute on function public.list_pending_approvals(uuid,uuid,uuid[],text[]) to service_role;

create or replace function public.claim_approval(
 p_actor_user_id uuid,p_tenant_id uuid,p_approval_id uuid,p_expected_version integer
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v public.executive_approval_inbox%rowtype; v_policy public.executive_approval_policies%rowtype; v_current bigint;
begin
 if coalesce(auth.jwt()->>'role','')<>'service_role' then raise exception using errcode='42501',message='EXECUTIVE_SERVICE_ROLE_REQUIRED'; end if;
 select * into v from public.executive_approval_inbox where tenant_id=p_tenant_id and id=p_approval_id for update;
 if not found then raise exception using errcode='P0002',message='APPROVAL_NOT_FOUND'; end if;
 if v.version<>p_expected_version then raise exception using errcode='40001',message='APPROVAL_STALE_VERSION'; end if;
 if v.expires_at<=now() then raise exception using errcode='22023',message='APPROVAL_EXPIRED'; end if;
 select * into v_policy from public.executive_approval_policies where tenant_id=p_tenant_id and id=v.policy_id and status='active';
 if not found or v.amount_idr>v_policy.max_amount_idr or not public.executive_approval_actor_has_role(p_actor_user_id,p_tenant_id,v.branch_id,v.category,v.required_role)
  then raise exception using errcode='42501',message='APPROVAL_POLICY_OR_ROLE_DENIED'; end if;
 if v.created_by=p_actor_user_id and not v_policy.self_approval_allowed then raise exception using errcode='42501',message='APPROVAL_SELF_APPROVAL_DENIED'; end if;
 select source_version into v_current from public.executive_pending_approval_sources
 where tenant_id=p_tenant_id and source_entity=v.source_entity and source_entity_id=v.source_entity_id;
 if not found or v_current<>v.source_version then raise exception using errcode='40001',message='APPROVAL_SOURCE_STALE'; end if;
 if v.status='claimed' and v.claimed_by<>p_actor_user_id and v.claim_expires_at>now()
  then raise exception using errcode='55P03',message='APPROVAL_CLAIMED_BY_OTHER'; end if;
 update public.executive_approval_inbox set status='claimed',claimed_by=p_actor_user_id,
  claim_expires_at=least(expires_at,now()+interval '5 minutes'),version=version+1,updated_at=now()
 where id=v.id returning * into v;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'executive.approval.claimed','executive_approval_inbox',v.id::text,
  jsonb_build_object('tenant_id',p_tenant_id,'source_entity',v.source_entity,'source_entity_id',v.source_entity_id,'version',v.version));
 return jsonb_build_object('approval_id',v.id,'claimed_by',v.claimed_by,'claim_expires_at',v.claim_expires_at,'version',v.version);
end $$;
revoke all on function public.claim_approval(uuid,uuid,uuid,integer) from public,anon,authenticated;
grant execute on function public.claim_approval(uuid,uuid,uuid,integer) to service_role;

create or replace function public.decide_approval(
 p_actor_user_id uuid,p_tenant_id uuid,p_approval_id uuid,p_decision text,p_reason text,p_expected_version integer
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v public.executive_approval_inbox%rowtype; v_policy public.executive_approval_policies%rowtype; v_current bigint; v_after bigint; v_result jsonb;
begin
 if coalesce(auth.jwt()->>'role','')<>'service_role' then raise exception using errcode='42501',message='EXECUTIVE_SERVICE_ROLE_REQUIRED'; end if;
 if p_decision not in ('approve','reject') or length(btrim(coalesce(p_reason,'')))<8 then raise exception using errcode='22023',message='APPROVAL_DECISION_INVALID'; end if;
 select * into v from public.executive_approval_inbox where tenant_id=p_tenant_id and id=p_approval_id for update;
 if not found or v.status<>'claimed' or v.claimed_by<>p_actor_user_id or v.claim_expires_at<=now() then
  raise exception using errcode='42501',message='APPROVAL_CLAIM_REQUIRED';
 end if;
 if v.version<>p_expected_version then raise exception using errcode='40001',message='APPROVAL_STALE_VERSION'; end if;
 select * into v_policy from public.executive_approval_policies where tenant_id=p_tenant_id and id=v.policy_id and status='active';
 if not found or v.amount_idr>v_policy.max_amount_idr or not public.executive_approval_actor_has_role(p_actor_user_id,p_tenant_id,v.branch_id,v.category,v.required_role)
  then raise exception using errcode='42501',message='APPROVAL_POLICY_OR_ROLE_DENIED'; end if;
 if v.created_by=p_actor_user_id and not v_policy.self_approval_allowed then raise exception using errcode='42501',message='APPROVAL_SELF_APPROVAL_DENIED'; end if;
 select source_version into v_current from public.executive_pending_approval_sources
 where tenant_id=p_tenant_id and source_entity=v.source_entity and source_entity_id=v.source_entity_id;
 if not found or v_current<>v.source_version then raise exception using errcode='40001',message='APPROVAL_SOURCE_STALE'; end if;
 if v.source_entity='purchase_requisition' then
  v_result:=public.erp_transition_purchase_requisition(v.source_entity_id,
    case when p_decision='approve' then 'approved' else 'rejected' end,p_actor_user_id,null);
 elsif v.source_entity='purchase_order' and p_decision='approve' then
  update public.purchase_orders set status='approved',approved_by=p_actor_user_id,updated_at=now()
   where id=v.source_entity_id and status='submitted' and requested_by<>p_actor_user_id;
  if not found then raise exception using errcode='40001',message='PURCHASE_ORDER_APPROVAL_SOURCE_STALE'; end if;
  insert into public.procurement_approval_events(tenant_id,entity_type,entity_id,event_type,actor_user_id,reason)
   values(p_tenant_id,'purchase_order',v.source_entity_id,'approved',p_actor_user_id,p_reason);
  v_result:=jsonb_build_object('source_entity_id',v.source_entity_id,'status','approved');
 elsif v.source_entity='hr_payroll_run' and p_decision='approve' then
  v_result:=public.hr_approve_payroll_run(v.source_entity_id,p_actor_user_id);
 elsif v.source_entity='hr_payroll_finance_posting' and p_decision='approve' then
  v_result:=public.hr_post_payroll_finance_posting(p_tenant_id,v.source_entity_id,p_actor_user_id);
 elsif v.source_entity='branch_operation_checklist_run' then
  update public.branch_operation_checklist_runs set approval_status=p_decision,approved_by=p_actor_user_id,
   approved_at=case when p_decision='approve' then now() else null end,approval_reason=p_reason,updated_at=now(),
   updated_by=p_actor_user_id,version=version+1
   where id=v.source_entity_id and branch_id=v.branch_id and status='completed' and approval_status='pending'
    and (completed_by<>p_actor_user_id or v_policy.self_approval_allowed);
  if not found then raise exception using errcode='40001',message='BRANCH_CHECKLIST_APPROVAL_SOURCE_STALE'; end if;
 else
  raise exception using errcode='22023',message='APPROVAL_SOURCE_DECISION_UNSUPPORTED';
 end if;
 if v.source_entity='purchase_requisition' then select (extract(epoch from updated_at)*1000)::bigint into v_after from public.purchase_requisitions where id=v.source_entity_id;
 elsif v.source_entity='purchase_order' then select (extract(epoch from updated_at)*1000)::bigint into v_after from public.purchase_orders where id=v.source_entity_id;
 elsif v.source_entity='hr_payroll_run' then select (extract(epoch from updated_at)*1000)::bigint into v_after from public.hr_payroll_runs where id=v.source_entity_id;
 elsif v.source_entity='hr_payroll_finance_posting' then select (extract(epoch from updated_at)*1000)::bigint into v_after from public.hr_payroll_finance_postings where id=v.source_entity_id;
 else select version::bigint into v_after from public.branch_operation_checklist_runs where id=v.source_entity_id;
 end if;
 insert into public.executive_approval_decisions(tenant_id,approval_id,actor_user_id,decision,reason,source_version_before,source_version_after)
 values(p_tenant_id,v.id,p_actor_user_id,p_decision,p_reason,v.source_version,coalesce(v_after,v.source_version+1));
 update public.executive_approval_inbox set status='decided',version=version+1,updated_at=now() where id=v.id;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'executive.approval.'||p_decision,v.source_entity,v.source_entity_id::text,
  jsonb_build_object('tenant_id',p_tenant_id,'approval_id',v.id,'source_version_before',v.source_version,'source_version_after',coalesce(v_after,v.source_version+1),'reason',p_reason));
 return jsonb_build_object('approval_id',v.id,'decision',p_decision,'source_entity',v.source_entity,
  'source_entity_id',v.source_entity_id,'source_version_before',v.source_version,'source_version_after',coalesce(v_after,v.source_version+1),'source_result',v_result);
end $$;
revoke all on function public.decide_approval(uuid,uuid,uuid,text,text,integer) from public,anon,authenticated;
grant execute on function public.decide_approval(uuid,uuid,uuid,text,text,integer) to service_role;

rollback;