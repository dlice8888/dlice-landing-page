-- Applied to staging as migration 20261020202841.
CREATE OR REPLACE FUNCTION public.erp_complete_production_batch(p_batch_id uuid, p_actual_good_quantity numeric, p_waste_quantity numeric, p_actual_consumptions jsonb, p_actor_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare batch public.production_batches%rowtype; recipe public.recipes%rowtype; ing record; it jsonb;
  actual_qty numeric(14,3); planned_qty numeric(14,3); move jsonb; movement_id uuid; consumption_count integer:=0;
begin
 if p_actual_good_quantity is null or p_actual_good_quantity<0 or p_waste_quantity is null or p_waste_quantity<0 then raise exception 'invalid_production_yield'; end if;
 if jsonb_typeof(p_actual_consumptions)<>'array' or jsonb_array_length(p_actual_consumptions)>100 then raise exception 'invalid_consumptions'; end if;
 select * into batch from public.production_batches where id=p_batch_id for update;
 if not found then raise exception 'production_batch_not_found'; end if;
 if batch.status<>'in_progress' then raise exception 'production_batch_not_in_progress'; end if;
 select * into recipe from public.recipes where id=batch.recipe_id and status='active' for share;
 if not found then raise exception 'active_recipe_required'; end if;
 if not exists(select 1 from public.branches where id=batch.branch_id and status='active') then raise exception 'branch_not_active'; end if;
 if exists(select 1 from public.production_consumptions where batch_id=batch.id) then raise exception 'production_consumption_already_recorded'; end if;
 for ing in select ri.inventory_item_id,ri.quantity_per_yield,ri.unit,ri.is_optional
   from public.recipe_ingredients ri where ri.recipe_id=recipe.id order by ri.inventory_item_id loop
   planned_qty:=round((ing.quantity_per_yield*batch.planned_quantity/recipe.yield_quantity)::numeric,3);
   select nullif(x->>'actual_quantity','')::numeric into actual_qty
   from jsonb_array_elements(p_actual_consumptions) x
   where x->>'inventory_item_id'=ing.inventory_item_id::text limit 1;
   if actual_qty is null then
     if not ing.is_optional then raise exception 'missing_actual_consumption'; else continue; end if;
   end if;
   if actual_qty<=0 or actual_qty>1000000 then raise exception 'invalid_actual_consumption'; end if;
   move:=public.erp_record_stock_movement(batch.branch_id,ing.inventory_item_id,'issue',actual_qty,
     'Production batch '||batch.batch_number||' actual ingredient consumption',p_actor_user_id);
   movement_id:=nullif(move->>'movement_id','')::uuid;
   insert into public.production_consumptions(batch_id,inventory_item_id,planned_quantity,actual_quantity,unit,stock_movement_id,recorded_by)
   values(batch.id,ing.inventory_item_id,planned_qty,actual_qty,ing.unit,movement_id,p_actor_user_id);
   consumption_count:=consumption_count+1;
 end loop;
 if exists(select 1 from jsonb_array_elements(p_actual_consumptions) x
   where not exists(select 1 from public.recipe_ingredients ri where ri.recipe_id=recipe.id and ri.inventory_item_id=(x->>'inventory_item_id')::uuid)) then
   raise exception 'ingredient_not_in_recipe';
 end if;
 update public.production_batches set status='completed',actual_good_quantity=p_actual_good_quantity,waste_quantity=p_waste_quantity,
   completed_by=p_actor_user_id,completed_at=now() where id=batch.id;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'erp_production_batch_completed','production_batch',batch.id::text,
   jsonb_build_object('branch_id',batch.branch_id,'recipe_id',recipe.id,'planned_quantity',batch.planned_quantity,'actual_good_quantity',p_actual_good_quantity,'waste_quantity',p_waste_quantity,'consumptions',consumption_count));
 return jsonb_build_object('ok',true,'batch_id',batch.id,'status','completed','actual_good_quantity',p_actual_good_quantity,'waste_quantity',p_waste_quantity,'consumptions_recorded',consumption_count);
end $function$
;
revoke all on function public.erp_complete_production_batch(uuid,numeric,numeric,jsonb,uuid) from public,anon,authenticated;
grant execute on function public.erp_complete_production_batch(uuid,numeric,numeric,jsonb,uuid) to service_role;
