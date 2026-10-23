-- Staging-first kitchen/KDS dispatch, POS idempotency, recipe stock issue and offline replay receipts.
-- This migration is intentionally additive. Product stock tracking stays disabled until a recipe is configured and an Owner enables it.

alter table public.products
  add column if not exists stock_tracking_enabled boolean not null default false;

alter table public.order_items
  add column if not exists modifier_snapshot jsonb not null default '[]'::jsonb check (jsonb_typeof(modifier_snapshot) = 'array'),
  add column if not exists substitution_snapshot jsonb not null default '[]'::jsonb check (jsonb_typeof(substitution_snapshot) = 'array');

alter table public.pos_sale_items
  add column if not exists modifier_snapshot jsonb not null default '[]'::jsonb check (jsonb_typeof(modifier_snapshot) = 'array'),
  add column if not exists substitution_snapshot jsonb not null default '[]'::jsonb check (jsonb_typeof(substitution_snapshot) = 'array');

create table if not exists public.product_modifiers (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete restrict,
  modifier_group text not null check (length(trim(modifier_group)) between 1 and 60),
  modifier_code text not null check (modifier_code ~ '^[a-z0-9][a-z0-9_-]{0,39}$'),
  name text not null check (length(trim(name)) between 1 and 100),
  price_delta_idr integer not null default 0 check (price_delta_idr between -100000000 and 100000000),
  is_required boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(product_id, modifier_group, modifier_code)
);
create index if not exists product_modifiers_product_active_idx on public.product_modifiers(product_id, is_active);

create table if not exists public.recipe_substitutions (
  id uuid primary key default gen_random_uuid(),
  recipe_ingredient_id uuid not null references public.recipe_ingredients(id) on delete restrict,
  substitute_inventory_item_id uuid not null references public.inventory_items(id) on delete restrict,
  quantity_factor numeric(14,6) not null default 1 check (quantity_factor > 0 and quantity_factor <= 1000),
  is_active boolean not null default true,
  approved_by uuid references auth.users(id) on delete restrict,
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  unique(recipe_ingredient_id, substitute_inventory_item_id)
);
create index if not exists recipe_substitutions_ingredient_active_idx on public.recipe_substitutions(recipe_ingredient_id, is_active);

create sequence if not exists public.kitchen_ticket_number_seq;

create table if not exists public.kitchen_tickets (
  id uuid primary key default gen_random_uuid(),
  ticket_number text not null unique default ('KIT-' || to_char(now() at time zone 'Asia/Jakarta','YYYYMMDD') || '-' || lpad(nextval('public.kitchen_ticket_number_seq')::text,6,'0')),
  branch_id uuid not null references public.branches(id) on delete restrict,
  order_id uuid references public.orders(id) on delete restrict,
  pos_sale_id uuid references public.pos_sales(id) on delete restrict,
  status text not null default 'queued' check (status in ('queued','accepted','preparing','ready','served','cancelled','blocked')),
  version integer not null default 1 check (version > 0),
  priority smallint not null default 3 check (priority between 1 and 5),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  accepted_at timestamptz,
  started_at timestamptz,
  ready_at timestamptz,
  served_at timestamptz,
  cancelled_at timestamptz,
  constraint kitchen_ticket_exactly_one_source check (num_nonnulls(order_id,pos_sale_id)=1)
);
create unique index if not exists kitchen_tickets_order_unique on public.kitchen_tickets(order_id) where order_id is not null;
create unique index if not exists kitchen_tickets_pos_sale_unique on public.kitchen_tickets(pos_sale_id) where pos_sale_id is not null;
create index if not exists kitchen_tickets_branch_status_created_idx on public.kitchen_tickets(branch_id,status,created_at);

create table if not exists public.kitchen_ticket_items (
  id uuid primary key default gen_random_uuid(),
  kitchen_ticket_id uuid not null references public.kitchen_tickets(id) on delete cascade,
  order_item_id uuid references public.order_items(id) on delete restrict,
  pos_sale_item_id uuid references public.pos_sale_items(id) on delete restrict,
  product_id uuid references public.products(id) on delete set null,
  product_name_snapshot text not null,
  quantity integer not null check (quantity between 1 and 1000),
  modifier_snapshot jsonb not null default '[]'::jsonb check (jsonb_typeof(modifier_snapshot)='array'),
  substitution_snapshot jsonb not null default '[]'::jsonb check (jsonb_typeof(substitution_snapshot)='array'),
  notes text,
  status text not null default 'queued' check (status in ('queued','preparing','ready','served','cancelled')),
  created_at timestamptz not null default now(),
  constraint kitchen_ticket_item_exactly_one_source check (num_nonnulls(order_item_id,pos_sale_item_id)=1)
);
create index if not exists kitchen_ticket_items_ticket_idx on public.kitchen_ticket_items(kitchen_ticket_id);

create table if not exists public.pos_idempotency_requests (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches(id) on delete restrict,
  actor_user_id uuid not null references auth.users(id) on delete restrict,
  idempotency_key text not null check (length(idempotency_key) between 8 and 120),
  payload_fingerprint text not null check (payload_fingerprint ~ '^[0-9a-f]{64}$'),
  response jsonb not null,
  created_at timestamptz not null default now(),
  unique(branch_id, actor_user_id, idempotency_key)
);
create index if not exists pos_idempotency_created_idx on public.pos_idempotency_requests(created_at);

create table if not exists public.offline_sync_receipts (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches(id) on delete restrict,
  actor_user_id uuid not null references auth.users(id) on delete restrict,
  device_id text not null check (length(device_id) between 1 and 120),
  client_operation_id text not null check (length(client_operation_id) between 8 and 120),
  operation_type text not null check (operation_type in ('pos-sale')),
  payload_fingerprint text not null check (payload_fingerprint ~ '^[0-9a-f]{64}$'),
  result jsonb not null,
  synced_at timestamptz not null default now(),
  unique(device_id, client_operation_id)
);
create index if not exists offline_sync_branch_synced_idx on public.offline_sync_receipts(branch_id,synced_at desc);

create or replace function public.dlice_dispatch_kitchen_ticket()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
declare ticket_id uuid;
begin
  if tg_table_name = 'pos_sales' then
    if new.payment_status <> 'paid' then return new; end if;
    insert into public.kitchen_tickets(branch_id,pos_sale_id)
    values(new.branch_id,new.id)
    on conflict do nothing
    returning id into ticket_id;
    if ticket_id is not null then
      insert into public.kitchen_ticket_items(kitchen_ticket_id,pos_sale_item_id,product_id,product_name_snapshot,quantity,modifier_snapshot,substitution_snapshot)
      select ticket_id,i.id,i.product_id,i.product_name_snapshot,i.quantity,i.modifier_snapshot,i.substitution_snapshot
      from public.pos_sale_items i where i.sale_id=new.id;
    end if;
    return new;
  end if;

  if new.payment_status = 'paid'
     and (new.operational_status in ('confirmed','preparing')
       or new.fulfillment_status in ('accepted','preparing')) then
    insert into public.kitchen_tickets(branch_id,order_id)
    values(new.branch_id,new.id)
    on conflict do nothing
    returning id into ticket_id;
    if ticket_id is not null then
      insert into public.kitchen_ticket_items(kitchen_ticket_id,order_item_id,product_id,product_name_snapshot,quantity,modifier_snapshot,substitution_snapshot)
      select ticket_id,i.id,i.product_id,i.product_name_snapshot,i.quantity,i.modifier_snapshot,i.substitution_snapshot
      from public.order_items i where i.order_id=new.id;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists dlice_kitchen_ticket_from_pos_sale on public.pos_sales;
create trigger dlice_kitchen_ticket_from_pos_sale
after insert on public.pos_sales
for each row execute function public.dlice_dispatch_kitchen_ticket();

drop trigger if exists dlice_kitchen_ticket_from_order on public.orders;
create trigger dlice_kitchen_ticket_from_order
after insert or update of payment_status, operational_status, fulfillment_status on public.orders
for each row execute function public.dlice_dispatch_kitchen_ticket();

create or replace function public.erp_create_pos_sale_idempotent(
  p_branch_id uuid, p_shift_id uuid, p_items jsonb, p_payment_method text,
  p_discount_idr bigint, p_customer_reference text, p_notes text,
  p_actor_user_id uuid, p_idempotency_key text
) returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare fingerprint text; prior public.pos_idempotency_requests%rowtype; result jsonb;
begin
  if p_idempotency_key is null or length(trim(p_idempotency_key)) < 8 or length(p_idempotency_key) > 120 then
    raise exception 'invalid_idempotency_key';
  end if;
  fingerprint := encode(digest(jsonb_build_object(
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
  result := public.erp_create_pos_sale(p_branch_id,p_shift_id,p_items,p_payment_method,p_discount_idr,p_customer_reference,p_notes,p_actor_user_id);
  insert into public.pos_idempotency_requests(branch_id,actor_user_id,idempotency_key,payload_fingerprint,response)
  values(p_branch_id,p_actor_user_id,p_idempotency_key,fingerprint,result);
  return result || jsonb_build_object('idempotent_replay',false);
end;
$$;

create or replace function public.erp_transition_kitchen_ticket(
  p_ticket_id uuid, p_next_status text, p_actor_user_id uuid, p_notes text default null
) returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare t public.kitchen_tickets%rowtype; allowed boolean:=false; now_at timestamptz:=now();
begin
  select * into t from public.kitchen_tickets where id=p_ticket_id for update;
  if not found then raise exception 'kitchen_ticket_not_found'; end if;
  allowed := case t.status
    when 'queued' then p_next_status in ('accepted','cancelled','blocked')
    when 'accepted' then p_next_status in ('preparing','cancelled','blocked')
    when 'preparing' then p_next_status in ('ready','cancelled','blocked')
    when 'ready' then p_next_status in ('served','preparing')
    when 'blocked' then p_next_status in ('accepted','cancelled')
    else false end;
  if not allowed then raise exception 'kitchen_ticket_transition_invalid'; end if;
  update public.kitchen_tickets set
    status=p_next_status, version=version+1, updated_at=now_at,
    accepted_at=case when p_next_status='accepted' then now_at else accepted_at end,
    started_at=case when p_next_status='preparing' and started_at is null then now_at else started_at end,
    ready_at=case when p_next_status='ready' then now_at else ready_at end,
    served_at=case when p_next_status='served' then now_at else served_at end,
    cancelled_at=case when p_next_status='cancelled' then now_at else cancelled_at end,
    notes=coalesce(nullif(left(trim(coalesce(p_notes,'')),500),''),notes)
  where id=p_ticket_id;
  update public.kitchen_ticket_items set status=case
    when p_next_status='preparing' then 'preparing'
    when p_next_status='ready' then 'ready'
    when p_next_status='served' then 'served'
    when p_next_status='cancelled' then 'cancelled'
    else status end
  where kitchen_ticket_id=p_ticket_id;
  if t.order_id is not null then
    update public.orders set
      fulfillment_status=case p_next_status
        when 'accepted' then 'accepted' when 'preparing' then 'preparing'
        when 'ready' then 'ready' when 'served' then 'fulfilled'
        when 'cancelled' then 'cancelled' else fulfillment_status end,
      operational_status=case p_next_status
        when 'preparing' then 'preparing'
        when 'ready' then 'ready_for_pickup'
        when 'served' then 'completed'
        when 'cancelled' then 'cancelled' else operational_status end,
      fulfilled_at=case when p_next_status='served' then now_at else fulfilled_at end,
      updated_at=now_at
    where id=t.order_id and payment_status='paid';
    insert into public.order_status_history(order_id,status_type,old_status,new_status,note)
    values(t.order_id,'operational',t.status,p_next_status,left(coalesce(p_notes,'KDS status update'),500));
  end if;
  insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
  values(p_actor_user_id,'kitchen_ticket_transition', 'kitchen_ticket',p_ticket_id::text,
    jsonb_build_object('branch_id',t.branch_id,'previous_status',t.status,'new_status',p_next_status,'version',t.version+1));
  return jsonb_build_object('ok',true,'ticket_id',p_ticket_id,'status',p_next_status,'version',t.version+1);
end;
$$;

do $$
declare t text;
begin
  foreach t in array array['product_modifiers','recipe_substitutions','kitchen_tickets','kitchen_ticket_items','pos_idempotency_requests','offline_sync_receipts'] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('revoke all on table public.%I from anon, authenticated',t);
  end loop;
end $$;

revoke all on function public.dlice_dispatch_kitchen_ticket() from public,anon,authenticated;
revoke all on function public.erp_create_pos_sale_idempotent(uuid,uuid,jsonb,text,bigint,text,text,uuid,text) from public,anon,authenticated;
revoke all on function public.erp_transition_kitchen_ticket(uuid,text,uuid,text) from public,anon,authenticated;
grant execute on function public.erp_create_pos_sale_idempotent(uuid,uuid,jsonb,text,bigint,text,text,uuid,text) to service_role;
grant execute on function public.erp_transition_kitchen_ticket(uuid,text,uuid,text) to service_role;
