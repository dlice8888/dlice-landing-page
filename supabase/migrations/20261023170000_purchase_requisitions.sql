-- Purchase requisitions: staging-first P1 procurement vertical slice.
-- API calls are authenticated and branch-scoped in dlice-orders; direct client table access is denied.
create sequence if not exists public.purchase_requisition_number_seq;

create table if not exists public.purchase_requisitions (
  id uuid primary key default gen_random_uuid(),
  requisition_number text not null unique default (
    'PR-' || to_char(now() at time zone 'Asia/Jakarta', 'YYYYMMDD') || '-' ||
    lpad(nextval('public.purchase_requisition_number_seq')::text, 5, '0')
  ),
  branch_id uuid not null references public.branches(id),
  status text not null default 'draft'
    check (status in ('draft','submitted','approved','rejected','converted','cancelled')),
  purpose text not null check (length(trim(purpose)) between 3 and 200),
  needed_by date,
  notes text,
  estimated_total_idr bigint not null default 0 check (estimated_total_idr >= 0),
  requested_by uuid not null,
  approved_by uuid,
  rejected_by uuid,
  converted_purchase_order_id uuid references public.purchase_orders(id),
  submitted_at timestamptz,
  approved_at timestamptz,
  rejected_at timestamptz,
  converted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.purchase_requisition_items (
  id uuid primary key default gen_random_uuid(),
  requisition_id uuid not null references public.purchase_requisitions(id) on delete cascade,
  inventory_item_id uuid not null references public.inventory_items(id),
  item_name_snapshot text not null,
  quantity numeric(14,3) not null check (quantity > 0),
  estimated_unit_cost_idr bigint not null default 0 check (estimated_unit_cost_idr >= 0),
  estimated_line_total_idr bigint not null default 0 check (estimated_line_total_idr >= 0),
  notes text,
  created_at timestamptz not null default now()
);

create index if not exists purchase_requisitions_branch_created_idx
  on public.purchase_requisitions(branch_id, created_at desc);
create index if not exists purchase_requisitions_status_created_idx
  on public.purchase_requisitions(status, created_at desc);
create index if not exists purchase_requisition_items_requisition_idx
  on public.purchase_requisition_items(requisition_id);
create index if not exists purchase_requisition_items_inventory_idx
  on public.purchase_requisition_items(inventory_item_id);

alter table public.purchase_requisitions enable row level security;
alter table public.purchase_requisition_items enable row level security;

drop policy if exists deny_direct_client_access_purchase_requisitions on public.purchase_requisitions;
create policy deny_direct_client_access_purchase_requisitions
  on public.purchase_requisitions for all to anon, authenticated
  using (false) with check (false);
drop policy if exists deny_direct_client_access_purchase_requisition_items on public.purchase_requisition_items;
create policy deny_direct_client_access_purchase_requisition_items
  on public.purchase_requisition_items for all to anon, authenticated
  using (false) with check (false);

revoke all on table public.purchase_requisitions from public, anon, authenticated;
revoke all on table public.purchase_requisition_items from public, anon, authenticated;
grant all on table public.purchase_requisitions, public.purchase_requisition_items to service_role;
revoke all on sequence public.purchase_requisition_number_seq from public, anon, authenticated;
grant usage, select on sequence public.purchase_requisition_number_seq to service_role;

create or replace function public.erp_create_purchase_requisition(
  p_branch_id uuid,
  p_items jsonb,
  p_requested_by uuid,
  p_purpose text,
  p_needed_by date default null,
  p_notes text default null
) returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  req public.purchase_requisitions%rowtype;
  line jsonb;
  item_id uuid;
  item_name text;
  qty numeric(14,3);
  unit_cost bigint;
  line_total bigint;
  total bigint := 0;
begin
  if p_branch_id is null or p_requested_by is null then raise exception 'invalid_requisition_actor_or_branch'; end if;
  if p_purpose is null or length(trim(p_purpose)) < 3 or length(p_purpose) > 200 then raise exception 'invalid_requisition_purpose'; end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) < 1 or jsonb_array_length(p_items) > 100 then
    raise exception 'invalid_requisition_items';
  end if;
  if not exists (select 1 from public.branches where id = p_branch_id and status = 'active') then
    raise exception 'branch_not_active';
  end if;

  insert into public.purchase_requisitions(branch_id, status, purpose, needed_by, notes, requested_by)
  values (p_branch_id, 'draft', trim(p_purpose), p_needed_by, left(nullif(trim(p_notes), ''), 500), p_requested_by)
  returning * into req;

  for line in select value from jsonb_array_elements(p_items) as t(value) loop
    item_id := nullif(line->>'inventory_item_id', '')::uuid;
    qty := nullif(line->>'quantity', '')::numeric;
    unit_cost := round(coalesce(nullif(line->>'estimated_unit_cost_idr', '')::numeric, 0))::bigint;
    if item_id is null or qty is null or qty <= 0 or qty > 100000 or unit_cost < 0 or unit_cost > 1000000000 then
      raise exception 'invalid_requisition_line';
    end if;
    select name into item_name from public.inventory_items where id = item_id and is_active = true;
    if item_name is null then raise exception 'inventory_item_not_found_or_inactive'; end if;
    line_total := round(qty * unit_cost)::bigint;
    total := total + line_total;
    insert into public.purchase_requisition_items(
      requisition_id, inventory_item_id, item_name_snapshot, quantity,
      estimated_unit_cost_idr, estimated_line_total_idr, notes
    ) values (
      req.id, item_id, item_name, qty, unit_cost, line_total, left(nullif(trim(line->>'notes'), ''), 250)
    );
  end loop;

  update public.purchase_requisitions set estimated_total_idr = total, updated_at = now()
  where id = req.id returning * into req;

  insert into public.admin_audit_logs(actor_user_id, action, entity_type, entity_id, metadata)
  values (p_requested_by, 'erp_purchase_requisition_created', 'purchase_requisition', req.id::text,
    jsonb_build_object('branch_id', req.branch_id, 'requisition_number', req.requisition_number,
      'estimated_total_idr', req.estimated_total_idr, 'line_count', jsonb_array_length(p_items)));

  return jsonb_build_object(
    'requisition', to_jsonb(req),
    'items', coalesce((select jsonb_agg(to_jsonb(i) order by i.created_at, i.id)
      from public.purchase_requisition_items i where i.requisition_id = req.id), '[]'::jsonb)
  );
end;
$$;

create or replace function public.erp_transition_purchase_requisition(
  p_requisition_id uuid,
  p_next_status text,
  p_actor_user_id uuid,
  p_supplier_id uuid default null
) returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  req public.purchase_requisitions%rowtype;
  po public.purchase_orders%rowtype;
  line record;
  po_code text;
  total bigint := 0;
  previous_status text;
begin
  if p_requisition_id is null or p_actor_user_id is null then raise exception 'invalid_requisition_actor_or_id'; end if;
  if p_next_status not in ('submitted','approved','rejected','converted','cancelled') then raise exception 'invalid_requisition_transition'; end if;
  select * into req from public.purchase_requisitions where id = p_requisition_id for update;
  if not found then raise exception 'purchase_requisition_not_found'; end if;

  if not (
    (req.status = 'draft' and p_next_status in ('submitted','cancelled')) or
    (req.status = 'submitted' and p_next_status in ('approved','rejected','cancelled')) or
    (req.status = 'approved' and p_next_status in ('converted','cancelled'))
  ) then raise exception 'purchase_requisition_transition_not_allowed'; end if;

  if p_next_status = 'converted' then
    if p_supplier_id is not null and not exists (
      select 1 from public.suppliers where id = p_supplier_id and is_active = true
    ) then raise exception 'supplier_not_found_or_inactive'; end if;
    select coalesce(sum(estimated_line_total_idr), 0) into total
      from public.purchase_requisition_items where requisition_id = req.id;
    po_code := 'PO-' || to_char(now() at time zone 'Asia/Jakarta', 'YYYYMMDD') || '-' ||
      upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6));
    insert into public.purchase_orders(
      po_number, branch_id, supplier_id, status, subtotal_idr, requested_by, approved_by, notes
    ) values (
      po_code, req.branch_id, p_supplier_id, 'draft', total, req.requested_by, p_actor_user_id,
      left('Dibuat dari ' || req.requisition_number || coalesce(' — ' || req.notes, ''), 500)
    ) returning * into po;

    for line in
      select inventory_item_id, item_name_snapshot, quantity, estimated_unit_cost_idr, estimated_line_total_idr
      from public.purchase_requisition_items where requisition_id = req.id order by created_at, id
    loop
      insert into public.purchase_order_items(
        purchase_order_id, inventory_item_id, item_name_snapshot, quantity, unit_cost_idr, line_total_idr
      ) values (
        po.id, line.inventory_item_id, line.item_name_snapshot, line.quantity,
        line.estimated_unit_cost_idr, line.estimated_line_total_idr
      );
    end loop;

    update public.purchase_requisitions
      set status = 'converted', converted_purchase_order_id = po.id, converted_at = now(), updated_at = now()
      where id = req.id returning * into req;

    insert into public.admin_audit_logs(actor_user_id, action, entity_type, entity_id, metadata)
    values (p_actor_user_id, 'erp_purchase_requisition_converted_to_po', 'purchase_requisition', req.id::text,
      jsonb_build_object('branch_id', req.branch_id, 'requisition_number', req.requisition_number,
        'purchase_order_id', po.id, 'po_number', po.po_number, 'estimated_total_idr', total));
    return jsonb_build_object('requisition', to_jsonb(req), 'purchase_order', to_jsonb(po));
  end if;

  previous_status := req.status;
  update public.purchase_requisitions
    set status = p_next_status,
        submitted_at = case when p_next_status = 'submitted' then now() else submitted_at end,
        approved_by = case when p_next_status = 'approved' then p_actor_user_id else approved_by end,
        approved_at = case when p_next_status = 'approved' then now() else approved_at end,
        rejected_by = case when p_next_status = 'rejected' then p_actor_user_id else rejected_by end,
        rejected_at = case when p_next_status = 'rejected' then now() else rejected_at end,
        updated_at = now()
    where id = req.id returning * into req;

  insert into public.admin_audit_logs(actor_user_id, action, entity_type, entity_id, metadata)
  values (p_actor_user_id, 'erp_purchase_requisition_' || p_next_status, 'purchase_requisition', req.id::text,
    jsonb_build_object('branch_id', req.branch_id, 'requisition_number', req.requisition_number,
      'previous_status', previous_status));

  return jsonb_build_object('requisition', to_jsonb(req));
end;
$$;

revoke all on function public.erp_create_purchase_requisition(uuid,jsonb,uuid,text,date,text) from public, anon, authenticated;
grant execute on function public.erp_create_purchase_requisition(uuid,jsonb,uuid,text,date,text) to service_role;
revoke all on function public.erp_transition_purchase_requisition(uuid,text,uuid,uuid) from public, anon, authenticated;
grant execute on function public.erp_transition_purchase_requisition(uuid,text,uuid,uuid) to service_role;
