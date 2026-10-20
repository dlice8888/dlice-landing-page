-- Atomic purchasing receipt and production consumption RPCs. Service-role only.
-- Applied to staging only; migration version 20261020195004.
create or replace function public.erp_receive_purchase_order(
 p_purchase_order_id uuid, p_receipt_number text, p_items jsonb,
 p_actor_user_id uuid, p_supplier_delivery_reference text default null, p_notes text default null
) returns jsonb language plpgsql security invoker set search_path=public as $$
declare po public.purchase_orders%rowtype; it jsonb; poi public.purchase_order_items%rowtype;
 qty numeric(14,3); already_received numeric(14,3); receipt_id uuid; line_count integer:=0;
 all_complete boolean:=true; result jsonb;
begin
 if p_receipt_number is null or length(trim(p_receipt_number))<5 or length(p_receipt_number)>60 then raise exception 'invalid_receipt_number'; end if;
 if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 or jsonb_array_length(p_items)>100 then raise exception 'invalid_receipt_items'; end if;
 select * into po from public.purchase_orders where id=p_purchase_order_id for update;
 if not found then raise exception 'purchase_order_not_found'; end if;
 if po.status not in ('ordered','partially_received') then raise exception 'purchase_order_not_receivable'; end if;
 if not exists(select 1 from public.branches where id=po.branch_id and status='active') then raise exception 'branch_not_active'; end if;
 if exists(select 1 from public.purchase_receipts where receipt_number=trim(p_receipt_number)) then raise exception 'duplicate_receipt_number'; end if;
 insert into public.purchase_receipts(receipt_number,purchase_order_id,branch_id,received_by,status,supplier_delivery_reference,notes)
 values(trim(p_receipt_number),po.id,po.branch_id,p_actor_user_id,'posted',left(p_supplier_delivery_reference,120),left(p_notes,500)) returning id into receipt_id;
 for it in select * from jsonb_array_elements(p_items) loop
  if coalesce(it->>'purchase_order_item_id','')='' then raise exception 'invalid_purchase_order_item'; end if;
  qty:=nullif(it->>'quantity_received','')::numeric;
  if qty is null or qty<=0 or qty>1000000 then raise exception 'invalid_received_quantity'; end if;
  select * into poi from public.purchase_order_items where id=(it->>'purchase_order_item_id')::uuid and purchase_order_id=po.id for update;
  if not found then raise exception 'purchase_order_item_mismatch'; end if;
  select coalesce(sum(pri.quantity_received),0) into already_received from public.purchase_receipt_items pri join public.purchase_receipts pr on pr.id=pri.receipt_id where pri.purchase_order_item_id=poi.id and pr.status='posted';
  if already_received+qty>poi.quantity then raise exception 'over_receipt'; end if;
  insert into public.purchase_receipt_items(receipt_id,purchase_order_item_id,inventory_item_id,quantity_received,unit_cost_idr) values(receipt_id,poi.id,poi.inventory_item_id,qty,poi.unit_cost_idr);
  result:=public.erp_record_stock_movement(po.branch_id,poi.inventory_item_id,'receipt',qty,'PO '||po.po_number||' / receipt '||trim(p_receipt_number)||coalesce(' — '||left(p_notes,200),''),p_actor_user_id);
  line_count:=line_count+1;
 end loop;
 if line_count=0 then raise exception 'empty_receipt'; end if;
 select not exists(
  select 1 from public.purchase_order_items x left join (
   select pri.purchase_order_item_id,sum(pri.quantity_received) received from public.purchase_receipt_items pri join public.purchase_receipts pr on pr.id=pri.receipt_id
   where pr.status='posted' group by pri.purchase_order_item_id
  ) r on r.purchase_order_item_id=x.id where x.purchase_order_id=po.id and coalesce(r.received,0)<x.quantity
 ) into all_complete;
 update public.purchase_orders set status=case when all_complete then 'received' else 'partially_received' end,updated_at=now() where id=po.id;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata) values(p_actor_user_id,'erp_purchase_receipt_posted','purchase_receipt',receipt_id::text,jsonb_build_object('purchase_order_id',po.id,'branch_id',po.branch_id,'receipt_number',p_receipt_number,'lines',line_count,'fully_received',all_complete));
 return jsonb_build_object('ok',true,'receipt_id',receipt_id,'receipt_number',p_receipt_number,'purchase_order_status',case when all_complete then 'received' else 'partially_received' end,'lines_received',line_count);
end $$;

create or replace function public.erp_complete_production_batch(
 p_batch_id uuid, p_actual_good_quantity numeric, p_waste_quantity numeric,
 p_actual_consumptions jsonb, p_actor_user_id uuid
) returns jsonb language plpgsql security invoker set search_path=public as $$
declare batch public.production_batches%rowtype; recipe public.recipes%rowtype; ing record; x jsonb;
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
 for ing in select ri.inventory_item_id,ri.quantity_per_yield,ri.unit,ri.is_optional from public.recipe_ingredients ri where ri.recipe_id=recipe.id loop
  planned_qty:=round((ing.quantity_per_yield*batch.planned_quantity/recipe.yield_quantity)::numeric,3);
  select nullif(c->>'actual_quantity','')::numeric into actual_qty from jsonb_array_elements(p_actual_consumptions) c where c->>'inventory_item_id'=ing.inventory_item_id::text limit 1;
  if actual_qty is null then if not ing.is_optional then raise exception 'missing_actual_consumption'; else continue; end if; end if;
  if actual_qty<=0 or actual_qty>1000000 then raise exception 'invalid_actual_consumption'; end if;
  move:=public.erp_record_stock_movement(batch.branch_id,ing.inventory_item_id,'issue',actual_qty,'Production batch '||batch.batch_number||' actual ingredient consumption',p_actor_user_id);
  movement_id:=nullif(move->>'movement_id','')::uuid;
  insert into public.production_consumptions(batch_id,inventory_item_id,planned_quantity,actual_quantity,unit,stock_movement_id,recorded_by) values(batch.id,ing.inventory_item_id,planned_qty,actual_qty,ing.unit,movement_id,p_actor_user_id);
  consumption_count:=consumption_count+1;
 end loop;
 if exists(select 1 from jsonb_array_elements(p_actual_consumptions) c where not exists(select 1 from public.recipe_ingredients ri where ri.recipe_id=recipe.id and ri.inventory_item_id=(c->>'inventory_item_id')::uuid)) then raise exception 'ingredient_not_in_recipe'; end if;
 update public.production_batches set status='completed',actual_good_quantity=p_actual_good_quantity,waste_quantity=p_waste_quantity,completed_by=p_actor_user_id,completed_at=now() where id=batch.id;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata) values(p_actor_user_id,'erp_production_batch_completed','production_batch',batch.id::text,jsonb_build_object('branch_id',batch.branch_id,'recipe_id',recipe.id,'planned_quantity',batch.planned_quantity,'actual_good_quantity',p_actual_good_quantity,'waste_quantity',p_waste_quantity,'consumptions',consumption_count));
 return jsonb_build_object('ok',true,'batch_id',batch.id,'status','completed','actual_good_quantity',p_actual_good_quantity,'waste_quantity',p_waste_quantity,'consumptions_recorded',consumption_count);
end $$;
revoke all on function public.erp_receive_purchase_order(uuid,text,jsonb,uuid,text,text) from public,anon,authenticated;
grant execute on function public.erp_receive_purchase_order(uuid,text,jsonb,uuid,text,text) to service_role;
revoke all on function public.erp_complete_production_batch(uuid,numeric,numeric,jsonb,uuid) from public,anon,authenticated;
grant execute on function public.erp_complete_production_batch(uuid,numeric,numeric,jsonb,uuid) to service_role;
