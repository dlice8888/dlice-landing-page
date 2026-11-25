-- DESIGN DRAFT ONLY. Apply after QUALITY_COMPLIANCE_ADAPTERS_EXTENSION_DRAFT.sql.
-- Source traceability bridge: posted receipts -> food lots -> POS sale stock issues.
-- Production output can be registered when an explicit inventory item and lot code
-- are supplied. Untracked items remain unaffected until a lot is first registered.

alter table public.food_lot_registry
 add column if not exists remaining_quantity numeric(14,3) not null default 0,
 add column if not exists expires_at date;
update public.food_lot_registry set remaining_quantity=quantity
 where remaining_quantity=0 and status='available';

alter table public.purchase_receipt_items
 add column if not exists supplier_lot_code text null,
 add column if not exists lot_expiry_at date null;
alter table public.production_batches
 add column if not exists output_inventory_item_id uuid null references public.inventory_items(id) on delete restrict,
 add column if not exists output_lot_code text null,
 add column if not exists output_expiry_at date null;
alter table public.food_recalls
 add column if not exists affected_pos_sale_count integer not null default 0
 check(affected_pos_sale_count>=0);

alter table public.food_lot_distributions drop constraint if exists food_lot_distributions_impact_type_check;
alter table public.food_lot_distributions add constraint food_lot_distributions_impact_type_check
 check(impact_type in ('branch','order','receipt','production_batch','pos_sale'));
alter table public.food_lot_distributions drop constraint if exists food_lot_distributions_tenant_id_lot_id_impact_type_impact_entity_id_key;
alter table public.food_recall_impacts drop constraint if exists food_recall_impacts_impact_type_check;
alter table public.food_recall_impacts add constraint food_recall_impacts_impact_type_check
 check(impact_type in ('branch','order','receipt','production_batch','pos_sale'));

create or replace function public.quality_process_receipt_item_lot(p_receipt_item_id uuid)
returns void language plpgsql security invoker set search_path=''
as $$
declare v record; r jsonb; v_lot_id uuid;
begin
 select pri.id,pri.receipt_id,pri.inventory_item_id,pri.quantity_received,pri.supplier_lot_code,pri.lot_expiry_at,
  pr.branch_id,pr.status as receipt_status,pr.received_by,b.tenant_id,ii.unit
 into v
 from public.purchase_receipt_items pri
 join public.purchase_receipts pr on pr.id=pri.receipt_id
 join public.branches b on b.id=pr.branch_id
 join public.inventory_items ii on ii.id=pri.inventory_item_id
 where pri.id=p_receipt_item_id for update of pri,pr;
 if not found or v.receipt_status<>'posted' then return; end if;
 if v.supplier_lot_code is null or length(btrim(v.supplier_lot_code))=0 then
  if exists(select 1 from public.food_lot_registry where tenant_id=v.tenant_id and branch_id=v.branch_id
    and inventory_item_id=v.inventory_item_id and status in ('available','quarantined','recalled','depleted')) then
   raise exception using errcode='23514',message='QUALITY_RECEIPT_LOT_CODE_REQUIRED_FOR_TRACKED_ITEM';
  end if;
  return;
 end if;
 if v.lot_expiry_at is not null and v.lot_expiry_at<current_date then
  raise exception using errcode='23514',message='QUALITY_RECEIPT_LOT_ALREADY_EXPIRED';
 end if;
 r:=public.quality_register_food_lot(v.tenant_id,v.branch_id,'receipt_item',v.id,v.supplier_lot_code,
  v.quantity_received,v.unit,'receipt-item:'||v.id::text,v.received_by);
 v_lot_id:=(r->>'lot_id')::uuid;
 if r->>'status'='registered' then
  update public.food_lot_registry set remaining_quantity=quantity,expires_at=v.lot_expiry_at
   where tenant_id=v.tenant_id and id=v_lot_id;
 end if;
 perform public.quality_link_food_lot_distribution(v.tenant_id,v.branch_id,v_lot_id,'receipt',v.receipt_id,
  v.quantity_received,'receipt-distribution:'||v.id::text,v.received_by);
end $$;
revoke all on function public.quality_process_receipt_item_lot(uuid) from public,anon,authenticated;
grant execute on function public.quality_process_receipt_item_lot(uuid) to service_role;

create or replace function public.quality_after_receipt_item_lot_write()
returns trigger language plpgsql security invoker set search_path=''
as $$ begin
 perform public.quality_process_receipt_item_lot(new.id);
 return new;
end $$;
revoke all on function public.quality_after_receipt_item_lot_write() from public,anon,authenticated;
drop trigger if exists quality_receipt_item_lot_after_write on public.purchase_receipt_items;
create trigger quality_receipt_item_lot_after_write after insert or update of supplier_lot_code,lot_expiry_at
 on public.purchase_receipt_items for each row execute function public.quality_after_receipt_item_lot_write();

create or replace function public.quality_after_receipt_posted_lot_sync()
returns trigger language plpgsql security invoker set search_path=''
as $$
declare v_item record;
begin
 if new.status='posted' and old.status is distinct from new.status then
  for v_item in select id from public.purchase_receipt_items where receipt_id=new.id loop
   perform public.quality_process_receipt_item_lot(v_item.id);
  end loop;
 end if;
 return new;
end $$;
revoke all on function public.quality_after_receipt_posted_lot_sync() from public,anon,authenticated;
drop trigger if exists quality_receipt_posted_lot_sync on public.purchase_receipts;
create trigger quality_receipt_posted_lot_sync after update of status on public.purchase_receipts
 for each row execute function public.quality_after_receipt_posted_lot_sync();

create or replace function public.quality_after_production_batch_completed()
returns trigger language plpgsql security invoker set search_path=''
as $$
declare v_tenant uuid; v_unit text; r jsonb; v_lot_id uuid;
begin
 if new.status<>'completed' or old.status='completed' then return new; end if;
 if new.output_inventory_item_id is null or new.output_lot_code is null or length(btrim(new.output_lot_code))=0 then
  if new.output_inventory_item_id is not null and exists(select 1 from public.food_lot_registry
   where branch_id=new.branch_id and inventory_item_id=new.output_inventory_item_id and status in ('available','quarantined','recalled')) then
   raise exception using errcode='23514',message='QUALITY_PRODUCTION_OUTPUT_LOT_CODE_REQUIRED_FOR_TRACKED_ITEM';
  end if;
  return new;
 end if;
 select b.tenant_id,ii.unit into v_tenant,v_unit from public.branches b
 join public.inventory_items ii on ii.id=new.output_inventory_item_id
 where b.id=new.branch_id;
 if not found then raise exception using errcode='23503',message='QUALITY_PRODUCTION_OUTPUT_ITEM_OR_BRANCH_NOT_FOUND'; end if;
 if new.output_expiry_at is not null and new.output_expiry_at<current_date then
  raise exception using errcode='23514',message='QUALITY_PRODUCTION_OUTPUT_LOT_ALREADY_EXPIRED';
 end if;
 r:=public.quality_register_food_lot(v_tenant,new.branch_id,'production_batch',new.id,new.output_lot_code,
  new.actual_good_quantity,v_unit,'production-batch:'||new.id::text,new.completed_by);
 v_lot_id:=(r->>'lot_id')::uuid;
 if r->>'status'='registered' then
  update public.food_lot_registry set inventory_item_id=new.output_inventory_item_id,
   remaining_quantity=quantity,expires_at=new.output_expiry_at where tenant_id=v_tenant and id=v_lot_id;
 end if;
 perform public.quality_link_food_lot_distribution(v_tenant,new.branch_id,v_lot_id,'production_batch',new.id,
  new.actual_good_quantity,'production-distribution:'||new.id::text,new.completed_by);
 return new;
end $$;
revoke all on function public.quality_after_production_batch_completed() from public,anon,authenticated;
drop trigger if exists quality_production_batch_lot_after_complete on public.production_batches;
create trigger quality_production_batch_lot_after_complete after update of status on public.production_batches
 for each row execute function public.quality_after_production_batch_completed();

create or replace function public.quality_auto_allocate_pos_sale_lots()
returns trigger language plpgsql security invoker set search_path=''
as $$
declare v_tenant uuid; v_cashier uuid; v_total_available numeric; v_remaining numeric; v_take numeric;
 v_lot public.food_lot_registry%rowtype; v_distribution uuid;
begin
 if new.movement_type<>'issue' or new.reference_type<>'pos_sale' then return new; end if;
 select b.tenant_id,ps.cashier_user_id into v_tenant,v_cashier
 from public.branches b join public.pos_sales ps on ps.branch_id=b.id
 where b.id=new.branch_id and ps.id=new.reference_id;
 if not found then raise exception using errcode='23503',message='QUALITY_POS_SALE_REFERENCE_NOT_FOUND'; end if;
 select coalesce(sum(remaining_quantity),0) into v_total_available
 from public.food_lot_registry where tenant_id=v_tenant and branch_id=new.branch_id
  and inventory_item_id=new.inventory_item_id and status='available'
  and (expires_at is null or expires_at>=current_date);
 if not exists(select 1 from public.food_lot_registry where tenant_id=v_tenant and branch_id=new.branch_id
   and inventory_item_id=new.inventory_item_id and status in ('available','quarantined','recalled','depleted')) then
  return new;
 end if;
 v_remaining:=abs(new.quantity);
 if v_total_available<v_remaining then
  raise exception using errcode='23514',message='QUALITY_LOT_TRACEABILITY_STOCK_INSUFFICIENT';
 end if;
 for v_lot in select * from public.food_lot_registry where tenant_id=v_tenant and branch_id=new.branch_id
  and inventory_item_id=new.inventory_item_id and status='available' and remaining_quantity>0
  and (expires_at is null or expires_at>=current_date)
  order by expires_at nulls last,created_at,id for update skip locked
 loop
  exit when v_remaining<=0;
  v_take:=least(v_remaining,v_lot.remaining_quantity);
  insert into public.food_lot_distributions(tenant_id,lot_id,branch_id,impact_type,impact_entity_id,quantity,idempotency_key,created_by)
  values(v_tenant,v_lot.id,new.branch_id,'pos_sale',new.reference_id,v_take,
   'pos-sale-movement:'||new.id::text||':'||v_lot.id::text,coalesce(new.created_by,v_cashier))
  returning id into v_distribution;
  update public.food_lot_registry set remaining_quantity=remaining_quantity-v_take,
   status=case when remaining_quantity-v_take=0 then 'depleted' else status end
   where tenant_id=v_tenant and id=v_lot.id;
  insert into public.quality_compliance_events(tenant_id,branch_id,entity_type,entity_id,action,actor_user_id,idempotency_key,evidence)
  values(v_tenant,new.branch_id,'food_lot_distribution',v_distribution,'food_lot.pos_sale_allocated',coalesce(new.created_by,v_cashier),
   'pos-sale-dist-event:'||new.id::text||':'||v_lot.id::text,
   jsonb_build_object('sale_id',new.reference_id,'stock_movement_id',new.id,'lot_id',v_lot.id,'quantity',v_take));
  v_remaining:=v_remaining-v_take;
 end loop;
 if v_remaining>0 then raise exception using errcode='23514',message='QUALITY_LOT_TRACEABILITY_ALLOCATION_INCOMPLETE'; end if;
 return new;
end $$;
revoke all on function public.quality_auto_allocate_pos_sale_lots() from public,anon,authenticated;
drop trigger if exists quality_pos_sale_stock_movement_lot_allocation on public.stock_movements;
create trigger quality_pos_sale_stock_movement_lot_allocation after insert on public.stock_movements
 for each row execute function public.quality_auto_allocate_pos_sale_lots();

