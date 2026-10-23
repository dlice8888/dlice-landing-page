-- Source mirror of staging migration 20261022124132_stock_transfers_and_counts.
-- Already applied in staging; this file restores migration source parity.
create table if not exists public.stock_transfers (
 id uuid primary key default gen_random_uuid(), transfer_number text not null unique,
 source_branch_id uuid not null references public.branches(id) on delete restrict,
 destination_branch_id uuid not null references public.branches(id) on delete restrict,
 status text not null default 'draft' check (status in ('draft','shipped','received','cancelled')),
 idempotency_key text not null unique, payload_fingerprint text not null, notes text,
 requested_by uuid references public.admin_profiles(user_id) on delete set null,
 shipped_by uuid references public.admin_profiles(user_id) on delete set null,
 received_by uuid references public.admin_profiles(user_id) on delete set null,
 shipped_at timestamptz, received_at timestamptz,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 constraint stock_transfers_distinct_branches check (source_branch_id <> destination_branch_id)
);
create table if not exists public.stock_transfer_items (
 id uuid primary key default gen_random_uuid(),
 transfer_id uuid not null references public.stock_transfers(id) on delete restrict,
 inventory_item_id uuid not null references public.inventory_items(id) on delete restrict,
 quantity numeric not null check (quantity > 0), created_at timestamptz not null default now(),
 unique (transfer_id, inventory_item_id)
);
create table if not exists public.stock_counts (
 id uuid primary key default gen_random_uuid(), count_number text not null unique,
 branch_id uuid not null references public.branches(id) on delete restrict,
 status text not null default 'draft' check (status in ('draft','posted','cancelled')),
 idempotency_key text not null unique, payload_fingerprint text not null, notes text,
 counted_by uuid references public.admin_profiles(user_id) on delete set null,
 posted_by uuid references public.admin_profiles(user_id) on delete set null,
 posted_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.stock_count_items (
 id uuid primary key default gen_random_uuid(),
 stock_count_id uuid not null references public.stock_counts(id) on delete restrict,
 inventory_item_id uuid not null references public.inventory_items(id) on delete restrict,
 expected_quantity numeric not null default 0 check (expected_quantity >= 0),
 counted_quantity numeric check (counted_quantity is null or counted_quantity >= 0),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 unique (stock_count_id, inventory_item_id)
);
create index if not exists stock_transfers_source_status_idx on public.stock_transfers(source_branch_id,status,created_at desc);
create index if not exists stock_transfers_destination_status_idx on public.stock_transfers(destination_branch_id,status,created_at desc);
create index if not exists stock_transfer_items_transfer_idx on public.stock_transfer_items(transfer_id);
create index if not exists stock_counts_branch_status_idx on public.stock_counts(branch_id,status,created_at desc);
create index if not exists stock_count_items_count_idx on public.stock_count_items(stock_count_id);
alter table public.stock_transfers enable row level security;
alter table public.stock_transfer_items enable row level security;
alter table public.stock_counts enable row level security;
alter table public.stock_count_items enable row level security;
drop policy if exists deny_direct_client_access on public.stock_transfers;
create policy deny_direct_client_access on public.stock_transfers for all to anon, authenticated using (false) with check (false);
drop policy if exists deny_direct_client_access on public.stock_transfer_items;
create policy deny_direct_client_access on public.stock_transfer_items for all to anon, authenticated using (false) with check (false);
drop policy if exists deny_direct_client_access on public.stock_counts;
create policy deny_direct_client_access on public.stock_counts for all to anon, authenticated using (false) with check (false);
drop policy if exists deny_direct_client_access on public.stock_count_items;
create policy deny_direct_client_access on public.stock_count_items for all to anon, authenticated using (false) with check (false);
revoke all on public.stock_transfers,public.stock_transfer_items,public.stock_counts,public.stock_count_items from anon,authenticated;
grant all on public.stock_transfers,public.stock_transfer_items,public.stock_counts,public.stock_count_items to service_role;
CREATE OR REPLACE FUNCTION public.erp_create_stock_count(p_count_number text, p_branch_id uuid, p_items jsonb, p_actor_user_id uuid, p_idempotency_key text, p_notes text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_id uuid; v_status text; v_fingerprint text; v_existing_fingerprint text; v_item jsonb; v_item_id uuid; v_expected numeric; v_count integer := 0;
begin
  if p_branch_id is null or not exists(select 1 from public.branches where id=p_branch_id and status='active') then raise exception 'inactive_or_missing_branch'; end if;
  if p_idempotency_key is null or length(trim(p_idempotency_key)) < 8 or length(p_idempotency_key) > 160 then raise exception 'invalid_idempotency_key'; end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 or jsonb_array_length(p_items) > 1000 then raise exception 'invalid_stock_count_items'; end if;
  v_fingerprint := md5(p_branch_id::text || ':' || p_items::text);
  select id,status,payload_fingerprint into v_id,v_status,v_existing_fingerprint from public.stock_counts where idempotency_key=p_idempotency_key;
  if found then
    if v_existing_fingerprint <> v_fingerprint then raise exception 'idempotency_key_payload_mismatch'; end if;
    return jsonb_build_object('id',v_id,'status',v_status,'replayed',true);
  end if;
  insert into public.stock_counts(count_number,branch_id,idempotency_key,payload_fingerprint,notes,counted_by)
  values(p_count_number,p_branch_id,p_idempotency_key,v_fingerprint,nullif(trim(p_notes),''),p_actor_user_id) returning id into v_id;
  for v_item in select value from jsonb_array_elements(p_items) loop
    v_item_id := (v_item->>'inventory_item_id')::uuid;
    if v_item_id is null or not exists(select 1 from public.inventory_items where id=v_item_id and is_active=true) then raise exception 'inactive_or_missing_inventory_item'; end if;
    insert into public.branch_inventory(branch_id,inventory_item_id,on_hand) values(p_branch_id,v_item_id,0) on conflict(branch_id,inventory_item_id) do nothing;
    select on_hand into v_expected from public.branch_inventory where branch_id=p_branch_id and inventory_item_id=v_item_id;
    insert into public.stock_count_items(stock_count_id,inventory_item_id,expected_quantity) values(v_id,v_item_id,v_expected);
    v_count := v_count+1;
  end loop;
  if v_count <> jsonb_array_length(p_items) then raise exception 'duplicate_stock_count_items'; end if;
  return jsonb_build_object('id',v_id,'status','draft','replayed',false);
end; $function$


CREATE OR REPLACE FUNCTION public.erp_create_stock_transfer(p_transfer_number text, p_source_branch_id uuid, p_destination_branch_id uuid, p_items jsonb, p_actor_user_id uuid, p_idempotency_key text, p_notes text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_id uuid; v_status text; v_fingerprint text; v_existing_fingerprint text; v_item jsonb; v_item_id uuid; v_qty numeric; v_count integer := 0;
begin
  if p_source_branch_id is null or p_destination_branch_id is null or p_source_branch_id = p_destination_branch_id then raise exception 'invalid_transfer_branches'; end if;
  if p_idempotency_key is null or length(trim(p_idempotency_key)) < 8 or length(p_idempotency_key) > 160 then raise exception 'invalid_idempotency_key'; end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 or jsonb_array_length(p_items) > 200 then raise exception 'invalid_transfer_items'; end if;
  v_fingerprint := md5(p_source_branch_id::text || ':' || p_destination_branch_id::text || ':' || p_items::text);
  select id,status,payload_fingerprint into v_id,v_status,v_existing_fingerprint from public.stock_transfers where idempotency_key=p_idempotency_key;
  if found then
    if v_existing_fingerprint <> v_fingerprint then raise exception 'idempotency_key_payload_mismatch'; end if;
    return jsonb_build_object('id',v_id,'status',v_status,'replayed',true);
  end if;
  if not exists(select 1 from public.branches where id=p_source_branch_id and status='active') or not exists(select 1 from public.branches where id=p_destination_branch_id and status='active') then raise exception 'inactive_or_missing_branch'; end if;
  insert into public.stock_transfers(transfer_number,source_branch_id,destination_branch_id,idempotency_key,payload_fingerprint,notes,requested_by)
  values (p_transfer_number,p_source_branch_id,p_destination_branch_id,p_idempotency_key,v_fingerprint,nullif(trim(p_notes),''),p_actor_user_id) returning id into v_id;
  for v_item in select value from jsonb_array_elements(p_items) loop
    v_item_id := (v_item->>'inventory_item_id')::uuid; v_qty := (v_item->>'quantity')::numeric;
    if v_item_id is null or v_qty is null or v_qty <= 0 or v_qty > 100000000 then raise exception 'invalid_transfer_item'; end if;
    if not exists(select 1 from public.inventory_items where id=v_item_id and is_active=true) then raise exception 'inactive_or_missing_inventory_item'; end if;
    insert into public.stock_transfer_items(transfer_id,inventory_item_id,quantity) values(v_id,v_item_id,v_qty);
    v_count := v_count + 1;
  end loop;
  if v_count <> jsonb_array_length(p_items) then raise exception 'duplicate_transfer_items'; end if;
  return jsonb_build_object('id',v_id,'status','draft','replayed',false);
end; $function$


CREATE OR REPLACE FUNCTION public.erp_post_stock_count(p_count_id uuid, p_actor_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_count public.stock_counts%rowtype; v_item record; v_current numeric; v_delta numeric; v_posted integer := 0;
begin
  select * into v_count from public.stock_counts where id=p_count_id for update;
  if not found then raise exception 'stock_count_not_found'; end if;
  if v_count.status='posted' then return jsonb_build_object('id',p_count_id,'status','posted','replayed',true); end if;
  if v_count.status <> 'draft' then raise exception 'stock_count_not_draft'; end if;
  if exists(select 1 from public.stock_count_items where stock_count_id=p_count_id and counted_quantity is null) then raise exception 'stock_count_items_incomplete'; end if;
  for v_item in select inventory_item_id,expected_quantity,counted_quantity from public.stock_count_items where stock_count_id=p_count_id order by inventory_item_id loop
    insert into public.branch_inventory(branch_id,inventory_item_id,on_hand) values(v_count.branch_id,v_item.inventory_item_id,0) on conflict(branch_id,inventory_item_id) do nothing;
    select on_hand into v_current from public.branch_inventory where branch_id=v_count.branch_id and inventory_item_id=v_item.inventory_item_id for update;
    v_delta := v_item.counted_quantity-v_current;
    if v_delta <> 0 then
      update public.branch_inventory set on_hand=v_item.counted_quantity,updated_at=now() where branch_id=v_count.branch_id and inventory_item_id=v_item.inventory_item_id;
      insert into public.stock_movements(branch_id,inventory_item_id,movement_type,quantity,reference_type,reference_id,notes,created_by)
      values(v_count.branch_id,v_item.inventory_item_id,case when v_delta>0 then 'adjustment_in' else 'adjustment_out' end,abs(v_delta),'stock_count',p_count_id,'Cycle count '||v_count.count_number||'; snapshot='||v_item.expected_quantity||'; before='||v_current,p_actor_user_id);
    end if;
    v_posted := v_posted+1;
  end loop;
  update public.stock_counts set status='posted',posted_by=p_actor_user_id,posted_at=now(),updated_at=now() where id=p_count_id;
  return jsonb_build_object('id',p_count_id,'status','posted','items_posted',v_posted);
end; $function$


CREATE OR REPLACE FUNCTION public.erp_transition_stock_transfer(p_transfer_id uuid, p_actor_user_id uuid, p_transition text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_transfer public.stock_transfers%rowtype; v_item record; v_balance numeric; v_count integer := 0;
begin
  if p_transition is null or p_transition not in ('ship','receive','cancel') then raise exception 'invalid_transfer_transition'; end if;
  select * into v_transfer from public.stock_transfers where id=p_transfer_id for update;
  if not found then raise exception 'stock_transfer_not_found'; end if;
  if (p_transition='ship' and v_transfer.status='shipped') or (p_transition='receive' and v_transfer.status='received') or (p_transition='cancel' and v_transfer.status='cancelled') then
    return jsonb_build_object('id',p_transfer_id,'status',v_transfer.status,'replayed',true);
  end if;
  if p_transition='ship' then
    if v_transfer.status <> 'draft' then raise exception 'stock_transfer_not_draft'; end if;
    for v_item in select inventory_item_id,quantity from public.stock_transfer_items where transfer_id=p_transfer_id order by inventory_item_id loop
      insert into public.branch_inventory(branch_id,inventory_item_id,on_hand) values(v_transfer.source_branch_id,v_item.inventory_item_id,0) on conflict(branch_id,inventory_item_id) do nothing;
      select on_hand into v_balance from public.branch_inventory where branch_id=v_transfer.source_branch_id and inventory_item_id=v_item.inventory_item_id for update;
      if v_balance < v_item.quantity then raise exception 'insufficient_stock_for_transfer'; end if;
      update public.branch_inventory set on_hand=on_hand-v_item.quantity,updated_at=now() where branch_id=v_transfer.source_branch_id and inventory_item_id=v_item.inventory_item_id;
      insert into public.stock_movements(branch_id,inventory_item_id,movement_type,quantity,reference_type,reference_id,notes,created_by)
      values(v_transfer.source_branch_id,v_item.inventory_item_id,'transfer_out',v_item.quantity,'stock_transfer',p_transfer_id,'Transfer '||v_transfer.transfer_number,p_actor_user_id);
      v_count := v_count+1;
    end loop;
    if v_count=0 then raise exception 'empty_stock_transfer'; end if;
    update public.stock_transfers set status='shipped',shipped_by=p_actor_user_id,shipped_at=now(),updated_at=now() where id=p_transfer_id;
    return jsonb_build_object('id',p_transfer_id,'status','shipped');
  elsif p_transition='receive' then
    if v_transfer.status <> 'shipped' then raise exception 'stock_transfer_not_shipped'; end if;
    for v_item in select inventory_item_id,quantity from public.stock_transfer_items where transfer_id=p_transfer_id order by inventory_item_id loop
      insert into public.branch_inventory(branch_id,inventory_item_id,on_hand) values(v_transfer.destination_branch_id,v_item.inventory_item_id,0) on conflict(branch_id,inventory_item_id) do nothing;
      perform 1 from public.branch_inventory where branch_id=v_transfer.destination_branch_id and inventory_item_id=v_item.inventory_item_id for update;
      update public.branch_inventory set on_hand=on_hand+v_item.quantity,updated_at=now() where branch_id=v_transfer.destination_branch_id and inventory_item_id=v_item.inventory_item_id;
      insert into public.stock_movements(branch_id,inventory_item_id,movement_type,quantity,reference_type,reference_id,notes,created_by)
      values(v_transfer.destination_branch_id,v_item.inventory_item_id,'transfer_in',v_item.quantity,'stock_transfer',p_transfer_id,'Transfer '||v_transfer.transfer_number,p_actor_user_id);
    end loop;
    update public.stock_transfers set status='received',received_by=p_actor_user_id,received_at=now(),updated_at=now() where id=p_transfer_id;
    return jsonb_build_object('id',p_transfer_id,'status','received');
  else
    if v_transfer.status <> 'draft' then raise exception 'only_draft_transfer_can_be_cancelled'; end if;
    update public.stock_transfers set status='cancelled',updated_at=now() where id=p_transfer_id;
    return jsonb_build_object('id',p_transfer_id,'status','cancelled');
  end if;
end; $function$


CREATE OR REPLACE FUNCTION public.erp_update_stock_count_item(p_count_id uuid, p_item_id uuid, p_counted_quantity numeric)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_status text;
begin
  if p_counted_quantity is null or p_counted_quantity < 0 or p_counted_quantity > 100000000 then raise exception 'invalid_counted_quantity'; end if;
  select status into v_status from public.stock_counts where id=p_count_id for update;
  if not found then raise exception 'stock_count_not_found'; end if;
  if v_status <> 'draft' then raise exception 'stock_count_not_draft'; end if;
  update public.stock_count_items set counted_quantity=p_counted_quantity,updated_at=now() where id=p_item_id and stock_count_id=p_count_id;
  if not found then raise exception 'stock_count_item_not_found'; end if;
  return true;
end; $function$


revoke all on function public.erp_create_stock_transfer(text,uuid,uuid,jsonb,uuid,text,text) from public,anon,authenticated;
revoke all on function public.erp_transition_stock_transfer(uuid,uuid,text) from public,anon,authenticated;
revoke all on function public.erp_create_stock_count(text,uuid,jsonb,uuid,text,text) from public,anon,authenticated;
revoke all on function public.erp_update_stock_count_item(uuid,uuid,numeric) from public,anon,authenticated;
revoke all on function public.erp_post_stock_count(uuid,uuid) from public,anon,authenticated;
grant execute on function public.erp_create_stock_transfer(text,uuid,uuid,jsonb,uuid,text,text) to service_role;
grant execute on function public.erp_transition_stock_transfer(uuid,uuid,text) to service_role;
grant execute on function public.erp_create_stock_count(text,uuid,jsonb,uuid,text,text) to service_role;
grant execute on function public.erp_update_stock_count_item(uuid,uuid,numeric) to service_role;
grant execute on function public.erp_post_stock_count(uuid,uuid) to service_role;
