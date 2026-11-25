-- DESIGN DRAFT ONLY. Apply after QUALITY_COMPLIANCE_SCHEMA_DRAFT.sql.
-- Every business workflow below is one SECURITY INVOKER RPC transaction. Do not
-- decompose it into multiple Supabase REST requests: inspection/quarantine/audit,
-- recall/impact/quarantine, and CAPA/verification/release must commit atomically.

create table if not exists public.food_lot_registry (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete restrict,
 branch_id uuid not null,
 lot_code text not null check(length(btrim(lot_code)) between 1 and 120),
 source_type text not null check(source_type in ('receipt_item','production_batch','branch_check')),
 source_id uuid not null,
 inventory_item_id uuid null,
 quantity numeric(14,3) not null check(quantity>0),
 unit text not null check(length(btrim(unit)) between 1 and 24),
 status text not null default 'available' check(status in ('available','quarantined','recalled','depleted','destroyed')),
 idempotency_key text not null check(length(idempotency_key) between 8 and 120),
 created_by uuid not null references auth.users(id) on delete restrict,
 created_at timestamptz not null default now(),
 unique(tenant_id,id),
 unique(tenant_id,idempotency_key),
 unique(tenant_id,branch_id,lot_code),
 foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict
);
create index if not exists food_lot_registry_source_idx on public.food_lot_registry(tenant_id,branch_id,source_type,source_id);
create index if not exists food_lot_registry_status_idx on public.food_lot_registry(tenant_id,branch_id,status,lot_code);

create table if not exists public.food_lot_distributions (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete restrict,
 lot_id uuid not null,
 branch_id uuid not null,
 impact_type text not null check(impact_type in ('branch','order','receipt','production_batch')),
 impact_entity_id uuid not null,
 quantity numeric(14,3) null check(quantity is null or quantity>=0),
 idempotency_key text not null check(length(idempotency_key) between 8 and 120),
 created_by uuid not null references auth.users(id) on delete restrict,
 created_at timestamptz not null default now(),
 unique(tenant_id,id),
 unique(tenant_id,idempotency_key),
 unique(tenant_id,lot_id,impact_type,impact_entity_id),
 foreign key(tenant_id,lot_id) references public.food_lot_registry(tenant_id,id) on delete restrict,
 foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict
);
create index if not exists food_lot_distributions_impact_idx on public.food_lot_distributions(tenant_id,impact_type,impact_entity_id);

alter table public.food_lot_quarantines
  add constraint food_lot_quarantines_recall_fk
  foreign key(tenant_id,recall_id) references public.food_recalls(tenant_id,id) on delete restrict;
create unique index if not exists food_lot_one_active_quarantine_uq
  on public.food_lot_quarantines(tenant_id,branch_id,lot_code) where status in ('held','release_pending');

create unique index if not exists food_safety_one_approved_policy_uq
  on public.food_safety_policies(tenant_id,branch_id,product_class) where status='approved';
create unique index if not exists supplier_quality_one_approved_policy_uq
  on public.supplier_quality_policies(tenant_id,branch_id,supplier_id) where status='approved';

alter table public.food_lot_registry enable row level security;
alter table public.food_lot_distributions enable row level security;
drop policy if exists service_role_only on public.food_lot_registry;
drop policy if exists service_role_only on public.food_lot_distributions;
create policy service_role_only on public.food_lot_registry for all to service_role using(true) with check(true);
create policy service_role_only on public.food_lot_distributions for all to service_role using(true) with check(true);
revoke all on public.food_lot_registry,public.food_lot_distributions from public,anon,authenticated;
grant select,insert,update on public.food_lot_registry to service_role;
grant select,insert on public.food_lot_distributions to service_role;

create or replace function public.quality_reject_append_only_mutation()
returns trigger language plpgsql security invoker set search_path=''
as $$ begin raise exception using errcode='55000',message='QUALITY_EVIDENCE_APPEND_ONLY'; end; $$;
revoke all on function public.quality_reject_append_only_mutation() from public,anon,authenticated;
drop trigger if exists food_safety_inspections_append_only on public.food_safety_inspections;
create trigger food_safety_inspections_append_only before update or delete on public.food_safety_inspections
for each row execute function public.quality_reject_append_only_mutation();
drop trigger if exists food_recall_impacts_append_only on public.food_recall_impacts;
create trigger food_recall_impacts_append_only before update or delete on public.food_recall_impacts
for each row execute function public.quality_reject_append_only_mutation();
drop trigger if exists quality_compliance_events_append_only on public.quality_compliance_events;
create trigger quality_compliance_events_append_only before update or delete on public.quality_compliance_events
for each row execute function public.quality_reject_append_only_mutation();
drop trigger if exists food_lot_distributions_append_only on public.food_lot_distributions;
create trigger food_lot_distributions_append_only before update or delete on public.food_lot_distributions
for each row execute function public.quality_reject_append_only_mutation();

create or replace function public.quality_approve_food_safety_policy(
 p_tenant_id uuid,p_branch_id uuid,p_policy_id uuid,p_actor_user_id uuid
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v public.food_safety_policies%rowtype;
begin
 select * into v from public.food_safety_policies where tenant_id=p_tenant_id and branch_id=p_branch_id and id=p_policy_id for update;
 if not found then raise exception using errcode='P0002',message='FOOD_SAFETY_POLICY_NOT_FOUND'; end if;
 if v.status not in ('draft','pending_approval') then raise exception using errcode='23514',message='FOOD_SAFETY_POLICY_NOT_APPROVABLE'; end if;
 if v.created_by=p_actor_user_id then raise exception using errcode='42501',message='INDEPENDENT_FOOD_SAFETY_POLICY_APPROVER_REQUIRED'; end if;
 if v.min_temp_c>v.max_temp_c or v.effective_until is not null and v.effective_until<=v.effective_from then
  raise exception using errcode='23514',message='FOOD_SAFETY_POLICY_INVALID';
 end if;
 update public.food_safety_policies set status='retired'
  where tenant_id=p_tenant_id and branch_id=p_branch_id and product_class=v.product_class and status='approved';
 update public.food_safety_policies set status='approved',approved_by=p_actor_user_id,approved_at=now()
  where tenant_id=p_tenant_id and id=p_policy_id returning * into v;
 insert into public.quality_compliance_events(tenant_id,branch_id,entity_type,entity_id,action,actor_user_id,idempotency_key,evidence)
 values(p_tenant_id,p_branch_id,'food_safety_inspection',v.id,'food_safety_policy.approved',p_actor_user_id,
  'policy-approve:'||v.id::text||':'||v.policy_version::text,jsonb_build_object('policy_version',v.policy_version,'product_class',v.product_class));
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'quality.food_safety.policy_approved','food_safety_policy',v.id::text,
  jsonb_build_object('tenant_id',p_tenant_id,'branch_id',p_branch_id,'policy_version',v.policy_version));
 return jsonb_build_object('policy_id',v.id,'status',v.status,'approved_by',v.approved_by);
end; $$;
revoke all on function public.quality_approve_food_safety_policy(uuid,uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.quality_approve_food_safety_policy(uuid,uuid,uuid,uuid) to service_role;

create or replace function public.quality_approve_supplier_quality_policy(
 p_tenant_id uuid,p_branch_id uuid,p_policy_id uuid,p_actor_user_id uuid
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v public.supplier_quality_policies%rowtype;
begin
 select * into v from public.supplier_quality_policies where tenant_id=p_tenant_id and branch_id=p_branch_id and id=p_policy_id for update;
 if not found then raise exception using errcode='P0002',message='SUPPLIER_QUALITY_POLICY_NOT_FOUND'; end if;
 if v.status not in ('draft','pending_approval') then raise exception using errcode='23514',message='SUPPLIER_QUALITY_POLICY_NOT_APPROVABLE'; end if;
 if v.created_by=p_actor_user_id then raise exception using errcode='42501',message='INDEPENDENT_SUPPLIER_POLICY_APPROVER_REQUIRED'; end if;
 update public.supplier_quality_policies set status='retired'
  where tenant_id=p_tenant_id and branch_id=p_branch_id and supplier_id=v.supplier_id and status='approved';
 update public.supplier_quality_policies set status='approved',approved_by=p_actor_user_id,approved_at=now()
  where tenant_id=p_tenant_id and id=p_policy_id returning * into v;
 insert into public.quality_compliance_events(tenant_id,branch_id,entity_type,entity_id,action,actor_user_id,idempotency_key,evidence)
 values(p_tenant_id,p_branch_id,'supplier_quality_inspection',v.id,'supplier_quality_policy.approved',p_actor_user_id,
  'supplier-policy-approve:'||v.id::text||':'||v.policy_version::text,jsonb_build_object('supplier_id',v.supplier_id,'policy_version',v.policy_version));
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'quality.supplier.policy_approved','supplier_quality_policy',v.id::text,
  jsonb_build_object('tenant_id',p_tenant_id,'branch_id',p_branch_id,'supplier_id',v.supplier_id,'policy_version',v.policy_version));
 return jsonb_build_object('policy_id',v.id,'status',v.status,'approved_by',v.approved_by);
end; $$;
revoke all on function public.quality_approve_supplier_quality_policy(uuid,uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.quality_approve_supplier_quality_policy(uuid,uuid,uuid,uuid) to service_role;

create or replace function public.quality_register_food_lot(
 p_tenant_id uuid,p_branch_id uuid,p_source_type text,p_source_id uuid,p_lot_code text,
 p_quantity numeric,p_unit text,p_idempotency_key text,p_actor_user_id uuid
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v_id uuid; v_item uuid; v_source_quantity numeric; v_status text; v_existing public.food_lot_registry%rowtype;
begin
 if p_source_type not in ('receipt_item','production_batch','branch_check') or p_quantity<=0
  or length(btrim(coalesce(p_lot_code,''))) not between 1 and 120
  or length(btrim(coalesce(p_unit,''))) not between 1 and 24
  or length(coalesce(p_idempotency_key,'')) not between 8 and 120 then
  raise exception using errcode='22023',message='INVALID_FOOD_LOT_REGISTRATION';
 end if;
 select * into v_existing from public.food_lot_registry where tenant_id=p_tenant_id and idempotency_key=p_idempotency_key;
 if found then
  if v_existing.branch_id<>p_branch_id or v_existing.source_type<>p_source_type or v_existing.source_id<>p_source_id
   or v_existing.lot_code<>p_lot_code or v_existing.quantity<>p_quantity then
   raise exception using errcode='23505',message='FOOD_LOT_IDEMPOTENCY_COLLISION';
  end if;
  return jsonb_build_object('status','duplicate','lot_id',v_existing.id,'lot_code',v_existing.lot_code);
 end if;
 if p_source_type='receipt_item' then
  select pri.inventory_item_id,pri.quantity_received,pr.status into v_item,v_source_quantity,v_status
   from public.purchase_receipt_items pri join public.purchase_receipts pr on pr.id=pri.receipt_id
   join public.branches b on b.id=pr.branch_id
   where pri.id=p_source_id and pr.branch_id=p_branch_id and b.tenant_id=p_tenant_id for update of pri,pr;
  if not found or v_status<>'posted' or p_quantity>v_source_quantity then
   raise exception using errcode='23514',message='POSTED_RECEIPT_ITEM_AND_QUANTITY_REQUIRED';
  end if;
 elsif p_source_type='production_batch' then
  select null::uuid,pb.actual_good_quantity,pb.status into v_item,v_source_quantity,v_status
   from public.production_batches pb join public.branches b on b.id=pb.branch_id
   where pb.id=p_source_id and pb.branch_id=p_branch_id and b.tenant_id=p_tenant_id for update of pb;
  if not found or v_status<>'completed' or v_source_quantity is null or p_quantity>v_source_quantity then
   raise exception using errcode='23514',message='COMPLETED_PRODUCTION_BATCH_AND_QUANTITY_REQUIRED';
  end if;
 else
  select null::uuid,1::numeric,cr.status into v_item,v_source_quantity,v_status
   from public.branch_operation_checklist_runs cr join public.branches b on b.id=cr.branch_id
   where cr.id=p_source_id and cr.branch_id=p_branch_id and b.tenant_id=p_tenant_id for update of cr;
  if not found or v_status<>'completed' then
   raise exception using errcode='23514',message='COMPLETED_BRANCH_CHECK_REQUIRED';
  end if;
 end if;
 insert into public.food_lot_registry(tenant_id,branch_id,lot_code,source_type,source_id,inventory_item_id,quantity,unit,idempotency_key,created_by)
 values(p_tenant_id,p_branch_id,btrim(p_lot_code),p_source_type,p_source_id,v_item,p_quantity,btrim(p_unit),p_idempotency_key,p_actor_user_id)
 returning id into v_id;
 insert into public.quality_compliance_events(tenant_id,branch_id,entity_type,entity_id,action,actor_user_id,idempotency_key,evidence)
 values(p_tenant_id,p_branch_id,'food_safety_inspection',v_id,'food_lot.registered',p_actor_user_id,p_idempotency_key,
  jsonb_build_object('lot_code',p_lot_code,'source_type',p_source_type,'source_id',p_source_id,'quantity',p_quantity,'unit',p_unit));
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'quality.food_lot.registered','food_lot_registry',v_id::text,
  jsonb_build_object('tenant_id',p_tenant_id,'branch_id',p_branch_id,'lot_code',p_lot_code,'source_type',p_source_type,'source_id',p_source_id));
 return jsonb_build_object('status','registered','lot_id',v_id,'lot_code',p_lot_code);
end; $$;
revoke all on function public.quality_register_food_lot(uuid,uuid,text,uuid,text,numeric,text,text,uuid) from public,anon,authenticated;
grant execute on function public.quality_register_food_lot(uuid,uuid,text,uuid,text,numeric,text,text,uuid) to service_role;

create or replace function public.quality_link_food_lot_distribution(
 p_tenant_id uuid,p_branch_id uuid,p_lot_id uuid,p_impact_type text,p_impact_entity_id uuid,
 p_quantity numeric,p_idempotency_key text,p_actor_user_id uuid
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v_lot public.food_lot_registry%rowtype; v_id uuid; v_target_branch uuid;
begin
 if p_impact_type not in ('branch','order','receipt','production_batch') or length(coalesce(p_idempotency_key,'')) not between 8 and 120
  or (p_quantity is not null and p_quantity<0) then raise exception using errcode='22023',message='INVALID_FOOD_LOT_DISTRIBUTION'; end if;
 select * into v_lot from public.food_lot_registry where tenant_id=p_tenant_id and id=p_lot_id for update;
 if not found or v_lot.status not in ('available','quarantined') then raise exception using errcode='23514',message='FOOD_LOT_NOT_DISTRIBUTABLE'; end if;
 if p_impact_type='branch' then
  select id into v_target_branch from public.branches where id=p_impact_entity_id and tenant_id=p_tenant_id;
 elsif p_impact_type='order' then
  select o.branch_id into v_target_branch from public.orders o join public.branches b on b.id=o.branch_id
   where o.id=p_impact_entity_id and b.tenant_id=p_tenant_id;
 elsif p_impact_type='receipt' then
  select pr.branch_id into v_target_branch from public.purchase_receipts pr join public.branches b on b.id=pr.branch_id
   where pr.id=p_impact_entity_id and b.tenant_id=p_tenant_id;
 else
  select pb.branch_id into v_target_branch from public.production_batches pb join public.branches b on b.id=pb.branch_id
   where pb.id=p_impact_entity_id and b.tenant_id=p_tenant_id;
 end if;
 if v_target_branch is null then raise exception using errcode='23503',message='FOOD_LOT_IMPACT_ENTITY_NOT_IN_TENANT'; end if;
 insert into public.food_lot_distributions(tenant_id,lot_id,branch_id,impact_type,impact_entity_id,quantity,idempotency_key,created_by)
 values(p_tenant_id,p_lot_id,v_target_branch,p_impact_type,p_impact_entity_id,p_quantity,p_idempotency_key,p_actor_user_id)
 on conflict(tenant_id,idempotency_key) do nothing returning id into v_id;
 if v_id is null then
  select id into v_id from public.food_lot_distributions where tenant_id=p_tenant_id and idempotency_key=p_idempotency_key;
  if v_id is null then raise exception using errcode='23505',message='FOOD_LOT_DISTRIBUTION_CONFLICT'; end if;
 end if;
 insert into public.quality_compliance_events(tenant_id,branch_id,entity_type,entity_id,action,actor_user_id,idempotency_key,evidence)
 values(p_tenant_id,p_branch_id,'food_safety_inspection',p_lot_id,'food_lot.distribution_linked',p_actor_user_id,p_idempotency_key,
  jsonb_build_object('impact_type',p_impact_type,'impact_entity_id',p_impact_entity_id,'impact_branch_id',v_target_branch));
 return jsonb_build_object('status','linked','distribution_id',v_id,'impact_branch_id',v_target_branch);
end; $$;
revoke all on function public.quality_link_food_lot_distribution(uuid,uuid,uuid,text,uuid,numeric,text,uuid) from public,anon,authenticated;
grant execute on function public.quality_link_food_lot_distribution(uuid,uuid,uuid,text,uuid,numeric,text,uuid) to service_role;

create or replace function public.quality_record_food_safety_inspection(
 p_tenant_id uuid,p_branch_id uuid,p_source_type text,p_source_id uuid,p_lot_code text,
 p_policy_id uuid,p_measured_temp_c numeric,p_declared_allergens text[],p_idempotency_key text,p_actor_user_id uuid
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v_policy public.food_safety_policies%rowtype; v_lot public.food_lot_registry%rowtype;
 v_missing text[]; v_in_range boolean; v_disposition text; v_id uuid; v_quarantine_id uuid;
 v_status text; v_source_ok boolean:=false; v_existing public.food_safety_inspections%rowtype;
begin
 if p_source_type not in ('receipt_item','production_batch','branch_check') or p_measured_temp_c is null
  or p_declared_allergens is null or length(coalesce(p_idempotency_key,'')) not between 8 and 120 then
  raise exception using errcode='22023',message='INVALID_FOOD_SAFETY_INSPECTION';
 end if;
 select * into v_existing from public.food_safety_inspections where tenant_id=p_tenant_id and idempotency_key=p_idempotency_key;
 if found then return jsonb_build_object('status','duplicate','inspection_id',v_existing.id,'disposition',v_existing.disposition); end if;
 select * into v_policy from public.food_safety_policies where tenant_id=p_tenant_id and branch_id=p_branch_id and id=p_policy_id
  and status='approved' and effective_from<=now() and (effective_until is null or effective_until>now()) for share;
 if not found then raise exception using errcode='23514',message='APPROVED_EFFECTIVE_FOOD_SAFETY_POLICY_REQUIRED'; end if;
 select * into v_lot from public.food_lot_registry where tenant_id=p_tenant_id and branch_id=p_branch_id
  and source_type=p_source_type and source_id=p_source_id and lot_code=p_lot_code for update;
 if not found or v_lot.status<>'available' then raise exception using errcode='23514',message='AVAILABLE_REGISTERED_FOOD_LOT_REQUIRED'; end if;
 if p_source_type='receipt_item' then
  select pr.status into v_status from public.purchase_receipt_items pri
   join public.purchase_receipts pr on pr.id=pri.receipt_id join public.branches b on b.id=pr.branch_id
   where pri.id=p_source_id and pr.branch_id=p_branch_id and b.tenant_id=p_tenant_id;
  v_source_ok:=found and v_status='posted';
 elsif p_source_type='production_batch' then
  select pb.status into v_status from public.production_batches pb join public.branches b on b.id=pb.branch_id
   where pb.id=p_source_id and pb.branch_id=p_branch_id and b.tenant_id=p_tenant_id;
  v_source_ok:=found and v_status='completed';
 else
  select cr.status into v_status from public.branch_operation_checklist_runs cr join public.branches b on b.id=cr.branch_id
   where cr.id=p_source_id and cr.branch_id=p_branch_id and b.tenant_id=p_tenant_id;
  v_source_ok:=found and v_status='completed';
 end if;
 if not v_source_ok then raise exception using errcode='23514',message='FOOD_SAFETY_SOURCE_NOT_VERIFIED'; end if;
 select coalesce(array_agg(a order by a),'{}'::text[]) into v_missing
  from unnest(v_policy.required_allergens) a where not (a=any(p_declared_allergens));
 v_in_range:=p_measured_temp_c between v_policy.min_temp_c and v_policy.max_temp_c;
 v_disposition:=case when v_in_range and cardinality(v_missing)=0 then 'accepted' else 'quarantined' end;
 insert into public.food_safety_inspections(tenant_id,branch_id,policy_id,source_type,source_id,lot_code,
  measured_temp_c,min_temp_c_snapshot,max_temp_c_snapshot,declared_allergens,missing_allergens,
  temperature_in_range,disposition,idempotency_key,inspected_by)
 values(p_tenant_id,p_branch_id,p_policy_id,p_source_type,p_source_id,p_lot_code,p_measured_temp_c,
  v_policy.min_temp_c,v_policy.max_temp_c,p_declared_allergens,v_missing,v_in_range,v_disposition,p_idempotency_key,p_actor_user_id)
 returning id into v_id;
 if v_disposition='quarantined' then
  insert into public.food_lot_quarantines(tenant_id,branch_id,lot_code,inspection_id,reason_codes,idempotency_key,created_by)
  values(p_tenant_id,p_branch_id,p_lot_code,v_id,
   array_remove(array[case when not v_in_range then 'TEMPERATURE_OUT_OF_POLICY' end,
     case when cardinality(v_missing)>0 then 'ALLERGEN_DECLARATION_MISMATCH' end],null),
   p_idempotency_key||':quarantine',p_actor_user_id) returning id into v_quarantine_id;
  update public.food_lot_registry set status='quarantined' where tenant_id=p_tenant_id and id=v_lot.id;
 end if;
 insert into public.quality_compliance_events(tenant_id,branch_id,entity_type,entity_id,action,actor_user_id,idempotency_key,evidence)
 values(p_tenant_id,p_branch_id,'food_safety_inspection',v_id,'food_safety.'||v_disposition,p_actor_user_id,p_idempotency_key,
  jsonb_build_object('lot_code',p_lot_code,'measured_temp_c',p_measured_temp_c,'missing_allergens',v_missing,'quarantine_id',v_quarantine_id));
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'quality.food_safety.'||v_disposition,'food_safety_inspection',v_id::text,
  jsonb_build_object('tenant_id',p_tenant_id,'branch_id',p_branch_id,'lot_code',p_lot_code,'quarantine_id',v_quarantine_id));
 return jsonb_build_object('status','recorded','inspection_id',v_id,'disposition',v_disposition,
  'missing_allergens',v_missing,'quarantine_id',v_quarantine_id);
end; $$;
revoke all on function public.quality_record_food_safety_inspection(uuid,uuid,text,uuid,text,uuid,numeric,text[],text,uuid) from public,anon,authenticated;
grant execute on function public.quality_record_food_safety_inspection(uuid,uuid,text,uuid,text,uuid,numeric,text[],text,uuid) to service_role;

create or replace function public.quality_initiate_food_recall(
 p_tenant_id uuid,p_branch_id uuid,p_lot_code text,p_reason text,p_severity text,
 p_idempotency_key text,p_actor_user_id uuid
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v_lot public.food_lot_registry%rowtype; v_id uuid; v_quarantine uuid;
 v_branch_count integer; v_order_count integer; v_existing public.food_recalls%rowtype;
begin
 if length(btrim(coalesce(p_lot_code,'')))=0 or length(btrim(coalesce(p_reason,'')))<3
  or p_severity not in ('low','medium','high','critical') or length(coalesce(p_idempotency_key,'')) not between 8 and 120 then
  raise exception using errcode='22023',message='INVALID_FOOD_RECALL_COMMAND';
 end if;
 select * into v_existing from public.food_recalls where tenant_id=p_tenant_id and idempotency_key=p_idempotency_key;
 if found then return jsonb_build_object('status','duplicate','recall_id',v_existing.id); end if;
 select * into v_lot from public.food_lot_registry where tenant_id=p_tenant_id and branch_id=p_branch_id
  and lot_code=p_lot_code for update;
 if not found or v_lot.status not in ('available','quarantined') then raise exception using errcode='23514',message='RECALLABLE_FOOD_LOT_REQUIRED'; end if;
 select count(distinct branch_id),count(distinct impact_entity_id) filter(where impact_type='order')
  into v_branch_count,v_order_count from public.food_lot_distributions where tenant_id=p_tenant_id and lot_id=v_lot.id;
 if v_branch_count=0 and v_order_count=0 then raise exception using errcode='23514',message='FOOD_RECALL_TRACEABILITY_INCOMPLETE'; end if;
 v_branch_count:=v_branch_count+case when not exists(select 1 from public.food_lot_distributions where tenant_id=p_tenant_id and lot_id=v_lot.id and branch_id=p_branch_id) then 1 else 0 end;
 insert into public.food_recalls(tenant_id,branch_id,lot_code,reason,severity,status,affected_branch_count,affected_order_count,idempotency_key,created_by)
 values(p_tenant_id,p_branch_id,p_lot_code,btrim(p_reason),p_severity,'initiated',v_branch_count,v_order_count,p_idempotency_key,p_actor_user_id)
 returning id into v_id;
 insert into public.food_recall_impacts(tenant_id,recall_id,impact_type,impact_entity_id,quantity)
 select p_tenant_id,v_id,impact_type,impact_entity_id,quantity from public.food_lot_distributions
 where tenant_id=p_tenant_id and lot_id=v_lot.id on conflict(tenant_id,recall_id,impact_type,impact_entity_id) do nothing;
 insert into public.food_lot_quarantines(tenant_id,branch_id,lot_code,recall_id,reason_codes,idempotency_key,created_by)
 values(p_tenant_id,p_branch_id,p_lot_code,v_id,array['FOOD_RECALL'],p_idempotency_key||':quarantine',p_actor_user_id)
 returning id into v_quarantine;
 update public.food_lot_registry set status='recalled' where tenant_id=p_tenant_id and id=v_lot.id;
 insert into public.quality_compliance_events(tenant_id,branch_id,entity_type,entity_id,action,actor_user_id,idempotency_key,evidence)
 values(p_tenant_id,p_branch_id,'food_recall',v_id,'food_recall.initiated',p_actor_user_id,p_idempotency_key,
  jsonb_build_object('lot_code',p_lot_code,'affected_branch_count',v_branch_count,'affected_order_count',v_order_count,'quarantine_id',v_quarantine));
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'quality.food_recall.initiated','food_recall',v_id::text,
  jsonb_build_object('tenant_id',p_tenant_id,'branch_id',p_branch_id,'lot_code',p_lot_code,'affected_branch_count',v_branch_count,'affected_order_count',v_order_count));
 return jsonb_build_object('status','initiated','recall_id',v_id,'quarantine_id',v_quarantine,
  'affected_branch_count',v_branch_count,'affected_order_count',v_order_count);
end; $$;
revoke all on function public.quality_initiate_food_recall(uuid,uuid,text,text,text,text,uuid) from public,anon,authenticated;
grant execute on function public.quality_initiate_food_recall(uuid,uuid,text,text,text,text,uuid) to service_role;

create or replace function public.quality_record_supplier_quality_inspection(
 p_tenant_id uuid,p_branch_id uuid,p_receipt_item_id uuid,p_policy_id uuid,p_findings jsonb,
 p_idempotency_key text,p_actor_user_id uuid
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v_supplier uuid; v_quantity numeric; v_policy public.supplier_quality_policies%rowtype;
 v_id uuid; v_quarantine uuid; v_capa uuid; v_nonconforming boolean; v_existing public.supplier_quality_inspections%rowtype;
begin
 if jsonb_typeof(p_findings)<>'array' or jsonb_array_length(p_findings)=0
  or length(coalesce(p_idempotency_key,'')) not between 8 and 120 then
  raise exception using errcode='22023',message='INVALID_SUPPLIER_QUALITY_INSPECTION';
 end if;
 select * into v_existing from public.supplier_quality_inspections where tenant_id=p_tenant_id and idempotency_key=p_idempotency_key;
 if found then return jsonb_build_object('status','duplicate','inspection_id',v_existing.id,'disposition',v_existing.disposition); end if;
 select po.supplier_id,pri.quantity_received into v_supplier,v_quantity
  from public.purchase_receipt_items pri join public.purchase_receipts pr on pr.id=pri.receipt_id
  join public.purchase_orders po on po.id=pr.purchase_order_id
  join public.branches b on b.id=pr.branch_id
  where pri.id=p_receipt_item_id and pr.branch_id=p_branch_id and b.tenant_id=p_tenant_id and pr.status='posted'
  for update of pri,pr;
 if not found then raise exception using errcode='P0002',message='POSTED_SUPPLIER_RECEIPT_ITEM_NOT_FOUND'; end if;
 select * into v_policy from public.supplier_quality_policies where tenant_id=p_tenant_id and branch_id=p_branch_id
  and id=p_policy_id and supplier_id=v_supplier and status='approved'
  and effective_from<=now() and (effective_until is null or effective_until>now()) for share;
 if not found then raise exception using errcode='23514',message='APPROVED_SUPPLIER_QUALITY_POLICY_REQUIRED'; end if;
 if exists(select 1 from jsonb_array_elements(p_findings) f
   where coalesce(f->>'code','')='' or coalesce(f->>'severity','') not in ('minor','major','critical')) then
  raise exception using errcode='22023',message='INVALID_SUPPLIER_QUALITY_FINDING';
 end if;
 select bool_or(f->>'severity' in ('major','critical') or v_policy.critical_finding_codes @> array[f->>'code'])
  into v_nonconforming from jsonb_array_elements(p_findings) f;
 v_nonconforming:=coalesce(v_nonconforming,false);
 insert into public.supplier_quality_inspections(tenant_id,branch_id,supplier_id,receipt_item_id,policy_id,findings,disposition,idempotency_key,inspected_by)
 values(p_tenant_id,p_branch_id,v_supplier,p_receipt_item_id,p_policy_id,p_findings,
  case when v_nonconforming then 'quarantined' else 'accepted_with_observation' end,p_idempotency_key,p_actor_user_id)
 returning id into v_id;
 if v_nonconforming then
  insert into public.supplier_quality_quarantines(tenant_id,branch_id,receipt_item_id,inspection_id,quantity,reason_codes,idempotency_key)
  values(p_tenant_id,p_branch_id,p_receipt_item_id,v_id,v_quantity,
    array(select distinct f->>'code' from jsonb_array_elements(p_findings) f),
    p_idempotency_key||':quarantine') returning id into v_quarantine;
  insert into public.supplier_corrective_actions(tenant_id,branch_id,supplier_id,inspection_id,status,created_by,idempotency_key)
  values(p_tenant_id,p_branch_id,v_supplier,v_id,'open',p_actor_user_id,p_idempotency_key||':capa')
  returning id into v_capa;
 end if;
 insert into public.quality_compliance_events(tenant_id,branch_id,entity_type,entity_id,action,actor_user_id,idempotency_key,evidence)
 values(p_tenant_id,p_branch_id,'supplier_quality_inspection',v_id,
  case when v_nonconforming then 'supplier_quality.quarantined' else 'supplier_quality.accepted_with_observation' end,
  p_actor_user_id,p_idempotency_key,jsonb_build_object('supplier_id',v_supplier,'receipt_item_id',p_receipt_item_id,'capa_id',v_capa,'quarantine_id',v_quarantine));
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,case when v_nonconforming then 'quality.supplier.quarantined' else 'quality.supplier.accepted' end,
  'supplier_quality_inspection',v_id::text,jsonb_build_object('tenant_id',p_tenant_id,'branch_id',p_branch_id,'supplier_id',v_supplier,'capa_id',v_capa));
 return jsonb_build_object('status','recorded','inspection_id',v_id,
  'disposition',case when v_nonconforming then 'quarantined' else 'accepted_with_observation' end,
  'capa_id',v_capa,'quarantine_id',v_quarantine);
end; $$;
revoke all on function public.quality_record_supplier_quality_inspection(uuid,uuid,uuid,uuid,jsonb,text,uuid) from public,anon,authenticated;
grant execute on function public.quality_record_supplier_quality_inspection(uuid,uuid,uuid,uuid,jsonb,text,uuid) to service_role;

create or replace function public.quality_submit_supplier_capa(
 p_tenant_id uuid,p_branch_id uuid,p_capa_id uuid,p_root_cause text,p_corrective_action text,
 p_preventive_action text,p_evidence_reference text,p_actor_user_id uuid
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v public.supplier_corrective_actions%rowtype;
begin
 select * into v from public.supplier_corrective_actions where tenant_id=p_tenant_id and branch_id=p_branch_id and id=p_capa_id for update;
 if not found then raise exception using errcode='P0002',message='SUPPLIER_CAPA_NOT_FOUND'; end if;
 if v.status not in ('open','in_progress') then raise exception using errcode='23514',message='SUPPLIER_CAPA_NOT_SUBMITTABLE'; end if;
 if length(btrim(coalesce(p_root_cause,'')))<3 or length(btrim(coalesce(p_corrective_action,'')))<3
  or length(btrim(coalesce(p_preventive_action,'')))<3 or length(btrim(coalesce(p_evidence_reference,'')))<3 then
  raise exception using errcode='22023',message='SUPPLIER_CAPA_EVIDENCE_REQUIRED';
 end if;
 update public.supplier_corrective_actions set status='submitted',root_cause=btrim(p_root_cause),
  corrective_action=btrim(p_corrective_action),preventive_action=btrim(p_preventive_action),
  evidence_reference=btrim(p_evidence_reference),submitted_by=p_actor_user_id where tenant_id=p_tenant_id and id=p_capa_id returning * into v;
 insert into public.quality_compliance_events(tenant_id,branch_id,entity_type,entity_id,action,actor_user_id,idempotency_key,evidence)
 values(p_tenant_id,p_branch_id,'supplier_capa',v.id,'supplier_capa.submitted',p_actor_user_id,
  'capa-submit:'||v.id::text||':'||md5(p_evidence_reference),jsonb_build_object('evidence_reference',p_evidence_reference));
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'quality.supplier.capa_submitted','supplier_corrective_action',v.id::text,
  jsonb_build_object('tenant_id',p_tenant_id,'branch_id',p_branch_id,'inspection_id',v.inspection_id));
 return jsonb_build_object('capa_id',v.id,'status',v.status,'submitted_by',v.submitted_by);
end; $$;
revoke all on function public.quality_submit_supplier_capa(uuid,uuid,uuid,text,text,text,text,uuid) from public,anon,authenticated;
grant execute on function public.quality_submit_supplier_capa(uuid,uuid,uuid,text,text,text,text,uuid) to service_role;

create or replace function public.quality_verify_supplier_capa(
 p_tenant_id uuid,p_branch_id uuid,p_capa_id uuid,p_decision text,p_evidence_reference text,
 p_release_quarantine boolean,p_actor_user_id uuid
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v public.supplier_corrective_actions%rowtype; v_released integer:=0;
begin
 if p_decision not in ('verified','rejected') or (p_release_quarantine and p_decision<>'verified')
  or length(btrim(coalesce(p_evidence_reference,'')))<3 then
  raise exception using errcode='22023',message='INVALID_SUPPLIER_CAPA_VERIFICATION';
 end if;
 select * into v from public.supplier_corrective_actions where tenant_id=p_tenant_id and branch_id=p_branch_id and id=p_capa_id for update;
 if not found then raise exception using errcode='P0002',message='SUPPLIER_CAPA_NOT_FOUND'; end if;
 if v.status<>'submitted' then raise exception using errcode='23514',message='SUPPLIER_CAPA_NOT_SUBMITTED'; end if;
 if p_actor_user_id in (v.created_by,v.submitted_by) then raise exception using errcode='42501',message='INDEPENDENT_SUPPLIER_CAPA_REVIEWER_REQUIRED'; end if;
 update public.supplier_corrective_actions set status=p_decision,verified_by=p_actor_user_id,verified_at=now(),
  evidence_reference=coalesce(evidence_reference,'')||' | verification: '||btrim(p_evidence_reference)
  where tenant_id=p_tenant_id and id=p_capa_id returning * into v;
 if p_release_quarantine then
  update public.supplier_quality_quarantines set status='released',released_by=p_actor_user_id,released_at=now()
   where tenant_id=p_tenant_id and inspection_id=v.inspection_id and status in ('held','release_pending');
  get diagnostics v_released=row_count;
  if v_released=0 then raise exception using errcode='23514',message='SUPPLIER_QUARANTINE_NOT_HELD'; end if;
 end if;
 insert into public.quality_compliance_events(tenant_id,branch_id,entity_type,entity_id,action,actor_user_id,idempotency_key,evidence)
 values(p_tenant_id,p_branch_id,'supplier_capa',v.id,'supplier_capa.'||p_decision,p_actor_user_id,
  'capa-verify:'||v.id::text||':'||p_decision,jsonb_build_object('release_quarantine',p_release_quarantine,'evidence_reference',p_evidence_reference));
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'quality.supplier.capa_'||p_decision,'supplier_corrective_action',v.id::text,
  jsonb_build_object('tenant_id',p_tenant_id,'branch_id',p_branch_id,'released_quarantines',v_released));
 return jsonb_build_object('capa_id',v.id,'status',v.status,'released_quarantines',v_released);
end; $$;
revoke all on function public.quality_verify_supplier_capa(uuid,uuid,uuid,text,text,boolean,uuid) from public,anon,authenticated;
grant execute on function public.quality_verify_supplier_capa(uuid,uuid,uuid,text,text,boolean,uuid) to service_role;
