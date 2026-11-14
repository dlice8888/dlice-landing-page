create or replace function public.dlice_get_command_center_summary(
  p_branch_ids uuid[],
  p_from_date date,
  p_through_date date
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'service_role_required' using errcode = '42501';
  end if;

  if p_branch_ids is null or cardinality(p_branch_ids) > 500 then
    raise exception 'invalid_branch_scope' using errcode = '22023';
  end if;

  if exists (
    select 1
    from public.branches b
    where b.id = any(p_branch_ids)
      and b.timezone not in ('Asia/Jakarta', 'Asia/Makassar', 'Asia/Jayapura')
  ) then
    raise exception 'unsupported_branch_timezone' using errcode = '22023';
  end if;

  if p_from_date is null
     or p_through_date is null
     or p_through_date < p_from_date
     or p_through_date - p_from_date > 92
     or p_through_date = date '9999-12-31' then
    raise exception 'invalid_reporting_period' using errcode = '22023';
  end if;

  return (
    with selected_branches as (
      select b.id, b.code, b.name, b.status, b.city, b.province, b.timezone
      from public.branches b
      where b.id = any(p_branch_ids)
    ),
    branch_metrics as (
      select
        b.*,
        sales.sales_idr,
        sales.paid_transactions,
        sales.average_order_value_idr,
        shifts.open_shifts,
        stock.low_stock_items,
        stock.out_of_stock_items,
        orders.pending_orders,
        kitchen.kds_backlog,
        requisitions.pending_requisitions,
        purchase_orders.open_purchase_orders,
        expenses.pending_expenses
      from selected_branches b
      cross join lateral (
        select
          coalesce(sum(s.total_idr), 0)::bigint as sales_idr,
          count(*)::integer as paid_transactions,
          coalesce(round(avg(s.total_idr)), 0)::bigint as average_order_value_idr
        from public.pos_sales s
        where s.branch_id = b.id
          and s.payment_status = 'paid'
          and s.created_at >= (p_from_date::timestamp at time zone b.timezone)
          and s.created_at < ((p_through_date + 1)::timestamp at time zone b.timezone)
      ) sales
      cross join lateral (
        select count(*)::integer as open_shifts
        from public.pos_shifts s
        where s.branch_id = b.id and s.status = 'open'
      ) shifts
      cross join lateral (
        select
          count(*) filter (
            where coalesce(bi.on_hand, 0) > 0
              and coalesce(bi.on_hand, 0) <= i.min_stock
          )::integer as low_stock_items,
          count(*) filter (where coalesce(bi.on_hand, 0) <= 0)::integer as out_of_stock_items
        from public.inventory_items i
        left join public.branch_inventory bi
          on bi.inventory_item_id = i.id and bi.branch_id = b.id
        where i.is_active = true and b.status <> 'planned'
      ) stock
      cross join lateral (
        select count(*)::integer as pending_orders
        from public.orders o
        where o.branch_id = b.id
          and o.operational_status not in ('completed', 'cancelled')
          and o.created_at >= (p_from_date::timestamp at time zone b.timezone)
          and o.created_at < ((p_through_date + 1)::timestamp at time zone b.timezone)
      ) orders
      cross join lateral (
        select count(*)::integer as kds_backlog
        from public.kitchen_tickets k
        where k.branch_id = b.id and k.status in ('queued', 'accepted', 'preparing', 'blocked')
      ) kitchen
      cross join lateral (
        select count(*)::integer as pending_requisitions
        from public.purchase_requisitions r
        where r.branch_id = b.id and r.status = 'submitted'
      ) requisitions
      cross join lateral (
        select count(*)::integer as open_purchase_orders
        from public.purchase_orders po
        where po.branch_id = b.id
          and po.status in ('submitted', 'approved', 'ordered', 'partially_received')
      ) purchase_orders
      cross join lateral (
        select count(*)::integer as pending_expenses
        from public.branch_expenses e
        where e.branch_id = b.id and e.status = 'pending_approval'
      ) expenses
    )
    select jsonb_build_object(
      'from_date', p_from_date,
      'through_date', p_through_date,
      'branch_summaries',
      coalesce(
        jsonb_agg(
          jsonb_build_object(
            'id', id,
            'code', code,
            'name', name,
            'status', status,
            'city', city,
            'province', province,
            'timezone', timezone,
            'sales_idr', sales_idr,
            'paid_transactions', paid_transactions,
            'average_order_value_idr', average_order_value_idr,
            'open_shifts', open_shifts,
            'low_stock_items', low_stock_items,
            'out_of_stock_items', out_of_stock_items,
            'pending_orders', pending_orders,
            'kds_backlog', kds_backlog,
            'pending_requisitions', pending_requisitions,
            'open_purchase_orders', open_purchase_orders,
            'pending_expenses', pending_expenses
          )
          order by code
        ),
        '[]'::jsonb
      )
    )
    from branch_metrics
  );
end;
$function$;

revoke all on function public.dlice_get_command_center_summary(uuid[], date, date)
  from public, anon, authenticated;
grant execute on function public.dlice_get_command_center_summary(uuid[], date, date)
  to service_role;
