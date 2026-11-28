-- DESIGN DRAFT ONLY — NOT A MIGRATION.
-- D04-F06/F07/F09: prep reservations, batch output and production-mode routing.
-- Depends on KITCHEN_PRODUCTION_WORKFLOWS_DRAFT.sql.
begin;

create table if not exists public.tenant_recipe_scopes (
 tenant_id uuid not null references public.tenants(id) on delete restrict,
 recipe_id uuid not null references public.recipes(id) on delete restrict,
 is_active boolean not null default true,approved_by uuid not null references auth.users(id) on delete restrict,
 approved_at timestamptz not null default now(),primary key(tenant_id,recipe_id)
);
alter table public.production_mode_policies add column if not exists allow_made_to_order_fallback boolean not null default false;
alter table public.tenant_recipe_scopes enable row level security;
alter table public.tenant_recipe_scopes force row level security;
create policy service_role_only on public.tenant_recipe_scopes for all to service_role using(true) with check(true);
revoke all on public.tenant_recipe_scopes from public,anon,authenticated;
grant select,insert,update on public.tenant_recipe_scopes to service_role;

create or replace function public.create_production_prep_plan(
 p_tenant_id uuid,p_branch_id uuid,p_actor_user_id uuid,p_service_date date,p_shift_id uuid,p_demand_reference text,p_items jsonb,p_idempotency_key text
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v_plan public.production_prep_plans%rowtype;v_item jsonb;v_recipe public.recipes%rowtype;v_plan_item public.production_prep_plan_items%rowtype;
 v_ing record;v_factor numeric;v_required numeric;v_on_hand numeric;v_reserved numeric;v_reservation jsonb:='[]'::jsonb;v_shift public.pos_shifts%rowtype;
begin
 if coalesce(auth.jwt()->>'role','')<>'service_role' then raise exception using errcode='42501',message='PRODUCTION_SERVICE_ROLE_REQUIRED';end if;
 if not public.pos_actor_can_access_branch(p_actor_user_id,p_tenant_id,p_branch_id) then raise exception using errcode='42501',message='PRODUCTION_BRANCH_SCOPE_DENIED';end if;
 if p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'prep_plan_items_required';end if;
 select * into v_shift from public.pos_shifts where id=p_shift_id and branch_id=p_branch_id and status='open' for share;
 if not found then raise exception 'prep_plan_open_shift_required';end if;
 insert into public.production_prep_plans(tenant_id,branch_id,service_date,shift_id,demand_reference,status,idempotency_key,created_by)
 values(p_tenant_id,p_branch_id,p_service_date,p_shift_id,left(p_demand_reference,120),'planned',p_idempotency_key,p_actor_user_id)
 on conflict(tenant_id,idempotency_key) do nothing returning * into v_plan;
 if not found then
  select * into v_plan from public.production_prep_plans where tenant_id=p_tenant_id and idempotency_key=p_idempotency_key;
  return jsonb_build_object('planId',v_plan.id,'tenantId',p_tenant_id,'branchId',p_branch_id,'status',v_plan.status,'ingredientReservations','[]'::jsonb,'replayed',true);
 end if;
 for v_item in select value from jsonb_array_elements(p_items) order by value->>'productId' loop
  select r.* into v_recipe from public.recipes r join public.tenant_recipe_scopes ts on ts.recipe_id=r.id and ts.tenant_id=p_tenant_id and ts.is_active
  where r.product_id=(v_item->>'productId')::uuid and r.status='active' and r.effective_from<=p_service_date
   and (r.effective_to is null or r.effective_to>=p_service_date) order by r.version desc limit 1;
  if not found then raise exception 'active_tenant_recipe_not_found';end if;
  insert into public.production_prep_plan_items(plan_id,product_id,recipe_id,recipe_version,planned_quantity)
  values(v_plan.id,(v_item->>'productId')::uuid,v_recipe.id,v_recipe.version,(v_item->>'quantity')::numeric)
  returning * into v_plan_item;
  for v_ing in select ri.inventory_item_id,ri.quantity_per_yield,ri.unit,ii.unit base_unit
   from public.recipe_ingredients ri join public.inventory_items ii on ii.id=ri.inventory_item_id
   where ri.recipe_id=v_recipe.id order by ri.inventory_item_id loop
   select c.factor into v_factor from public.inventory_uom_conversions c where c.tenant_id=p_tenant_id
    and c.inventory_item_id=v_ing.inventory_item_id and c.from_unit=v_ing.unit and c.to_unit=v_ing.base_unit
    and c.effective_from<=p_service_date and (c.effective_to is null or c.effective_to>=p_service_date)
    order by c.effective_from desc limit 1;
   if v_ing.unit<>v_ing.base_unit and v_factor is null then raise exception 'prep_plan_uom_conversion_missing';end if;
   v_required:=round(v_ing.quantity_per_yield*(v_item->>'quantity')::numeric/v_recipe.yield_quantity*coalesce(v_factor,1),3);
   select on_hand into v_on_hand from public.branch_inventory where branch_id=p_branch_id and inventory_item_id=v_ing.inventory_item_id for update;
   if not found then raise exception 'prep_plan_inventory_balance_missing';end if;
   select coalesce(sum(planned_quantity),0) into v_reserved from public.production_prep_plan_reservations
    where tenant_id=p_tenant_id and branch_id=p_branch_id and inventory_item_id=v_ing.inventory_item_id and status='reserved';
   if v_on_hand-v_reserved<v_required then raise exception 'prep_plan_insufficient_stock';end if;
   insert into public.production_prep_plan_reservations(tenant_id,branch_id,plan_item_id,inventory_item_id,planned_quantity,unit,status)
   values(p_tenant_id,p_branch_id,v_plan_item.id,v_ing.inventory_item_id,v_required,v_ing.base_unit,'reserved');
   v_reservation:=v_reservation||jsonb_build_array(jsonb_build_object('inventoryItemId',v_ing.inventory_item_id,'quantity',v_required,'unit',v_ing.base_unit));
  end loop;
 end loop;
 update public.production_prep_plans set status='reserved',updated_at=now() where id=v_plan.id;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'production_prep_plan_reserved','production_prep_plan',v_plan.id::text,jsonb_build_object('tenant_id',p_tenant_id,'branch_id',p_branch_id,'demand_reference',p_demand_reference));
 return jsonb_build_object('planId',v_plan.id,'tenantId',p_tenant_id,'branchId',p_branch_id,'status','planned','ingredientReservations',v_reservation,'replayed',false);
end $$;
revoke all on function public.create_production_prep_plan(uuid,uuid,uuid,date,uuid,text,jsonb,text) from public,anon,authenticated;
grant execute on function public.create_production_prep_plan(uuid,uuid,uuid,date,uuid,text,jsonb,text) to service_role;

create or replace function public.record_production_batch_output()
returns trigger language plpgsql security definer set search_path=''
as $$
declare v_tenant uuid;v_product uuid;
begin
 if new.status='completed' and old.status is distinct from 'completed' and coalesce(new.actual_good_quantity,0)>0 then
  select b.tenant_id,r.product_id into v_tenant,v_product from public.branches b join public.recipes r on r.id=new.recipe_id
   where b.id=new.branch_id;
  if v_tenant is null or v_product is null then raise exception 'production_batch_tenant_or_product_missing';end if;
  insert into public.production_batch_outputs(tenant_id,branch_id,batch_id,product_id,available_quantity)
  values(v_tenant,new.branch_id,new.id,v_product,new.actual_good_quantity)
  on conflict(batch_id) do nothing;
 end if;
 return new;
end $$;
drop trigger if exists trg_record_production_batch_output on public.production_batches;
create trigger trg_record_production_batch_output after update of status on public.production_batches
for each row execute function public.record_production_batch_output();

create or replace function public.route_production_mode(
 p_tenant_id uuid,p_branch_id uuid,p_actor_user_id uuid,p_product_id uuid,p_quantity numeric,p_order_id uuid,p_idempotency_key text
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v_policy public.production_mode_policies%rowtype;v_output public.production_batch_outputs%rowtype;v_job public.production_jobs%rowtype;
begin
 if coalesce(auth.jwt()->>'role','')<>'service_role' then raise exception using errcode='42501',message='PRODUCTION_SERVICE_ROLE_REQUIRED';end if;
 if not public.pos_actor_can_access_branch(p_actor_user_id,p_tenant_id,p_branch_id) then raise exception using errcode='42501',message='PRODUCTION_BRANCH_SCOPE_DENIED';end if;
 if p_quantity<=0 then raise exception 'production_quantity_invalid';end if;
 select * into v_policy from public.production_mode_policies where tenant_id=p_tenant_id and branch_id=p_branch_id and product_id=p_product_id and is_active;
 if not found then raise exception 'production_mode_policy_missing';end if;
 if v_policy.mode='made_to_order' then
  insert into public.production_jobs(tenant_id,branch_id,product_id,order_id,quantity,status,idempotency_key,created_by)
  values(p_tenant_id,p_branch_id,p_product_id,p_order_id,p_quantity,'queued',p_idempotency_key,p_actor_user_id)
  on conflict(tenant_id,idempotency_key) do nothing returning * into v_job;
  if not found then select * into v_job from public.production_jobs where tenant_id=p_tenant_id and idempotency_key=p_idempotency_key;end if;
  return jsonb_build_object('tenantId',p_tenant_id,'branchId',p_branch_id,'mode','made_to_order','productionJobId',v_job.id,'reason','policy_made_to_order');
 end if;
 select * into v_output from public.production_batch_outputs where tenant_id=p_tenant_id and branch_id=p_branch_id and product_id=p_product_id
  and available_quantity-reserved_quantity>=p_quantity order by created_at for update limit 1;
 if found then
  update public.production_batch_outputs set reserved_quantity=reserved_quantity+p_quantity,updated_at=now() where id=v_output.id;
  return jsonb_build_object('tenantId',p_tenant_id,'branchId',p_branch_id,'mode','batch','batchId',v_output.batch_id,'reason','batch_output_reserved');
 end if;
 if v_policy.allow_made_to_order_fallback then
  insert into public.production_jobs(tenant_id,branch_id,product_id,order_id,quantity,status,idempotency_key,created_by)
  values(p_tenant_id,p_branch_id,p_product_id,p_order_id,p_quantity,'queued',p_idempotency_key,p_actor_user_id)
  on conflict(tenant_id,idempotency_key) do nothing returning * into v_job;
  if not found then select * into v_job from public.production_jobs where tenant_id=p_tenant_id and idempotency_key=p_idempotency_key;end if;
  return jsonb_build_object('tenantId',p_tenant_id,'branchId',p_branch_id,'mode','made_to_order','productionJobId',v_job.id,'reason','batch_depleted_fallback');
 end if;
 raise exception 'batch_output_insufficient';
end $$;
revoke all on function public.route_production_mode(uuid,uuid,uuid,uuid,numeric,uuid,text) from public,anon,authenticated;
grant execute on function public.route_production_mode(uuid,uuid,uuid,uuid,numeric,uuid,text) to service_role;

create or replace function public.reconcile_production_batch_ledger(p_tenant_id uuid,p_branch_id uuid,p_batch_id uuid)
returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v_rows jsonb;v_bad integer;
begin
 if coalesce(auth.jwt()->>'role','')<>'service_role' then raise exception using errcode='42501',message='PRODUCTION_SERVICE_ROLE_REQUIRED';end if;
 if not exists(select 1 from public.production_batches pb join public.branches b on b.id=pb.branch_id
  where pb.id=p_batch_id and pb.branch_id=p_branch_id and b.tenant_id=p_tenant_id) then raise exception using errcode='42501',message='PRODUCTION_BATCH_SCOPE_DENIED';end if;
 select count(*) filter(where pc.actual_quantity<>sm.quantity)::integer,
  coalesce(jsonb_agg(jsonb_build_object('inventoryItemId',pc.inventory_item_id,'actualQuantity',pc.actual_quantity,
   'stockMovementQuantity',sm.quantity,'stockMovementId',sm.id)),'[]'::jsonb)
 into v_bad,v_rows from public.production_consumptions pc join public.stock_movements sm on sm.id=pc.stock_movement_id
 where pc.batch_id=p_batch_id;
 if coalesce(v_bad,0)>0 then raise exception 'production_stock_ledger_mismatch';end if;
 return jsonb_build_object('tenantId',p_tenant_id,'branchId',p_branch_id,'ingredients',v_rows);
end $$;
revoke all on function public.reconcile_production_batch_ledger(uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.reconcile_production_batch_ledger(uuid,uuid,uuid) to service_role;

rollback;