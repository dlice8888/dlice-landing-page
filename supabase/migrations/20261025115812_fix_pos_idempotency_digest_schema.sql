-- Fix idempotent POS sale fingerprinting on Supabase.
-- pgcrypto's digest() is installed in the extensions schema, while this function
-- deliberately uses search_path=public. Qualify the function to avoid 42883.
CREATE OR REPLACE FUNCTION public.erp_create_pos_sale_idempotent(p_branch_id uuid, p_shift_id uuid, p_items jsonb, p_payment_method text, p_discount_idr bigint, p_customer_reference text, p_notes text, p_actor_user_id uuid, p_idempotency_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare
  fingerprint text; prior public.pos_idempotency_requests%rowtype; result jsonb;
  sold record; input_item jsonb; modifier jsonb; modifier_row public.product_modifiers%rowtype;
  selected_modifiers jsonb; modifier_delta bigint; adjusted_unit bigint; adjusted_subtotal bigint;
  recipe_row public.recipes%rowtype; ingredient public.recipe_ingredients%rowtype;
  requested_substitution jsonb; substitution public.recipe_substitutions%rowtype;
  chosen_inventory_id uuid; consumption numeric(14,3); available_qty numeric(14,3);
  substitutions_snapshot jsonb; substitution_count integer;
begin
  if p_idempotency_key is null or length(trim(p_idempotency_key)) < 8 or length(p_idempotency_key) > 120 then
    raise exception 'invalid_idempotency_key';
  end if;
  if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 or jsonb_array_length(p_items)>50 then
    raise exception 'invalid_items';
  end if;
  fingerprint := encode(extensions.digest(jsonb_build_object(
    'branch_id',p_branch_id,'shift_id',p_shift_id,'items',p_items,
    'payment_method',p_payment_method,'discount_idr',p_discount_idr,
    'customer_reference',p_customer_reference,'notes',p_notes
  )::text,'sha256'),'hex');
  perform pg_advisory_xact_lock(hashtextextended(p_branch_id::text || ':' || p_actor_user_id::text || ':' || p_idempotency_key,0));
  select * into prior from public.pos_idempotency_requests
  where branch_id=p_branch_id and actor_user_id=p_actor_user_id and idempotency_key=p_idempotency_key
  for update;
  if found then
    if prior.payload_fingerprint <> fingerprint then raise exception 'idempotency_key_payload_mismatch'; end if;
    return prior.response || jsonb_build_object('idempotent_replay',true);
  end if;

  -- Existing atomic POS routine remains the source of truth for shift, branch, price and payment checks.
  result := public.erp_create_pos_sale(p_branch_id,p_shift_id,
    (select jsonb_agg(jsonb_build_object('slug',items.value->>'slug','quantity',items.value->>'quantity')) from jsonb_array_elements(p_items) as items(value)),
    p_payment_method,p_discount_idr,p_customer_reference,p_notes,p_actor_user_id);

  -- Apply selected modifiers to line totals and preserve the exact sale-time selection.
  for sold in
    select si.id,si.product_id,si.quantity,si.unit_price_idr,si.line_total_idr,p.slug,p.stock_tracking_enabled
    from public.pos_sale_items si join public.products p on p.id=si.product_id
    where si.sale_id=(result->>'sale_id')::uuid order by si.id
  loop
    select items.value into input_item from jsonb_array_elements(p_items) as items(value) where items.value->>'slug'=sold.slug limit 1;
    selected_modifiers := '[]'::jsonb;
    modifier_delta := 0;
    if input_item is not null and jsonb_typeof(input_item->'modifiers')='array' then
      for modifier in select value from jsonb_array_elements(input_item->'modifiers') loop
        select * into modifier_row from public.product_modifiers
        where product_id=sold.product_id and modifier_code=modifier->>'code' and is_active=true for share;
        if not found then raise exception 'invalid_modifier'; end if;
        if exists(select 1 from jsonb_array_elements(selected_modifiers) as selected(value) where selected.value->>'code'=modifier_row.modifier_code) then
          raise exception 'duplicate_modifier';
        end if;
        modifier_delta := modifier_delta + modifier_row.price_delta_idr;
        selected_modifiers := selected_modifiers || jsonb_build_array(jsonb_build_object(
          'code',modifier_row.modifier_code,'group',modifier_row.modifier_group,
          'name',modifier_row.name,'price_delta_idr',modifier_row.price_delta_idr
        ));
      end loop;
    end if;
    if exists(
      select 1 from public.product_modifiers required_modifier
      where required_modifier.product_id=sold.product_id and required_modifier.is_active and required_modifier.is_required
        and not exists(select 1 from jsonb_array_elements(selected_modifiers) as chosen(value) where chosen.value->>'group'=required_modifier.modifier_group)
    ) then raise exception 'required_modifier_missing'; end if;
    adjusted_unit := sold.unit_price_idr::bigint + modifier_delta;
    if adjusted_unit < 0 or adjusted_unit > 2147483647 then raise exception 'modifier_price_out_of_range'; end if;
    update public.pos_sale_items set unit_price_idr=adjusted_unit::integer,
      line_total_idr=adjusted_unit* sold.quantity, modifier_snapshot=selected_modifiers
    where id=sold.id;
  end loop;

  select coalesce(sum(line_total_idr),0) into adjusted_subtotal
  from public.pos_sale_items where sale_id=(result->>'sale_id')::uuid;
  if adjusted_subtotal < (select discount_idr from public.pos_sales where id=(result->>'sale_id')::uuid) then
    raise exception 'discount_exceeds_subtotal_after_modifiers';
  end if;
  update public.pos_sales set subtotal_idr=adjusted_subtotal,
    total_idr=adjusted_subtotal-discount_idr
  where id=(result->>'sale_id')::uuid;
  if p_payment_method='cash' then
    update public.pos_shifts set expected_cash_idr=expected_cash_idr +
      ((select total_idr from public.pos_sales where id=(result->>'sale_id')::uuid) - (result->>'total_idr')::bigint)
    where id=p_shift_id;
  end if;

  -- Deduct theoretical recipe consumption only for products explicitly enabled for stock tracking.
  -- Every balance is locked and checked inside this transaction; any failure rolls back sale, cash and ticket.
  for sold in
    select si.id,si.product_id,si.quantity,p.slug,p.stock_tracking_enabled,p.name
    from public.pos_sale_items si join public.products p on p.id=si.product_id
    where si.sale_id=(result->>'sale_id')::uuid order by si.product_id,si.id
  loop
    if sold.stock_tracking_enabled then
      select * into recipe_row from public.recipes
      where product_id=sold.product_id and status='active'
      order by version desc limit 1 for share;
      if not found then raise exception 'active_recipe_required'; end if;
      substitutions_snapshot := '[]'::jsonb;
      substitution_count := 0;
      for ingredient in
        select ri.* from public.recipe_ingredients ri
        where ri.recipe_id=recipe_row.id order by ri.inventory_item_id,ri.id
      loop
        chosen_inventory_id := ingredient.inventory_item_id;
        consumption := round((sold.quantity::numeric * ingredient.quantity_per_yield / recipe_row.yield_quantity),3);
        requested_substitution := null;
        if input_item is not null and jsonb_typeof(input_item->'substitutions')='array' then
          select requested.value into requested_substitution from jsonb_array_elements(input_item->'substitutions') as requested(value)
          where requested.value->>'recipe_ingredient_id'=ingredient.id::text limit 1;
        end if;
        if requested_substitution is not null then
          select * into substitution from public.recipe_substitutions
          where recipe_ingredient_id=ingredient.id
            and substitute_inventory_item_id=(requested_substitution->>'substitute_inventory_item_id')::uuid
            and is_active=true and approved_by is not null and approved_at is not null for share;
          if not found then raise exception 'invalid_recipe_substitution'; end if;
          chosen_inventory_id := substitution.substitute_inventory_item_id;
          consumption := round(consumption * substitution.quantity_factor,3);
          substitutions_snapshot := substitutions_snapshot || jsonb_build_array(jsonb_build_object(
            'recipe_ingredient_id',ingredient.id,'original_inventory_item_id',ingredient.inventory_item_id,
            'substitute_inventory_item_id',chosen_inventory_id,'quantity_factor',substitution.quantity_factor
          ));
          substitution_count := substitution_count+1;
        end if;
        insert into public.branch_inventory(branch_id,inventory_item_id,on_hand)
        values(p_branch_id,chosen_inventory_id,0) on conflict(branch_id,inventory_item_id) do nothing;
        select on_hand into available_qty from public.branch_inventory
        where branch_id=p_branch_id and inventory_item_id=chosen_inventory_id for update;
        if available_qty < consumption then raise exception 'insufficient_stock'; end if;
        update public.branch_inventory set on_hand=on_hand-consumption,updated_at=now()
        where branch_id=p_branch_id and inventory_item_id=chosen_inventory_id;
        insert into public.stock_movements(branch_id,inventory_item_id,movement_type,quantity,reference_type,reference_id,notes,created_by)
        values(p_branch_id,chosen_inventory_id,'issue',consumption,'pos_sale',(result->>'sale_id')::uuid,
          left('POS sale '||(result->>'transaction_code')||'; recipe '||recipe_row.id,500),p_actor_user_id);
      end loop;
      update public.pos_sale_items set substitution_snapshot=substitutions_snapshot where id=sold.id;
    end if;
  end loop;

  update public.kitchen_ticket_items kti set
    modifier_snapshot=psi.modifier_snapshot,
    substitution_snapshot=psi.substitution_snapshot
  from public.kitchen_tickets kt, public.pos_sale_items psi
  where kt.pos_sale_id=(result->>'sale_id')::uuid and kti.kitchen_ticket_id=kt.id and kti.pos_sale_item_id=psi.id;

  result := result || jsonb_build_object(
    'subtotal_idr',adjusted_subtotal,
    'total_idr',(select total_idr from public.pos_sales where id=(result->>'sale_id')::uuid)
  );
  insert into public.pos_idempotency_requests(branch_id,actor_user_id,idempotency_key,payload_fingerprint,response)
  values(p_branch_id,p_actor_user_id,p_idempotency_key,fingerprint,result);
  return result || jsonb_build_object('idempotent_replay',false);
end;
$function$

