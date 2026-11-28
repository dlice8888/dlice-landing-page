-- DESIGN DRAFT ONLY — NOT A MIGRATION.
-- D04-F01/F03/F04/F05/F06/F07/F09: KDS stations, SLA, recipe costing, prep planning and production mode.
-- Depends on POS_SHIFT_CASH_DRAFT.sql for pos_actor_can_access_branch().
begin;

create table if not exists public.kitchen_stations (
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete restrict,
 branch_id uuid not null,code text not null,name text not null,is_active boolean not null default true,
 is_default boolean not null default false,priority integer not null default 100,
 foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict,
 unique(tenant_id,branch_id,code)
);
create table if not exists public.kitchen_station_assignments (
 tenant_id uuid not null references public.tenants(id) on delete restrict,station_id uuid not null references public.kitchen_stations(id) on delete restrict,
 user_id uuid not null references auth.users(id) on delete restrict,is_active boolean not null default true,
 primary key(station_id,user_id)
);
create table if not exists public.kitchen_station_product_categories (
 tenant_id uuid not null references public.tenants(id) on delete restrict,station_id uuid not null references public.kitchen_stations(id) on delete restrict,
 product_category text not null,priority integer not null default 100,
 primary key(station_id,product_category)
);
create table if not exists public.kitchen_ticket_station_assignments (
 tenant_id uuid not null references public.tenants(id) on delete restrict,branch_id uuid not null,
 kitchen_ticket_item_id uuid not null references public.kitchen_ticket_items(id) on delete cascade,
 station_id uuid not null references public.kitchen_stations(id) on delete restrict,assigned_at timestamptz not null default now(),
 primary key(kitchen_ticket_item_id),
 foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict
);
create table if not exists public.kitchen_ticket_events (
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete restrict,
 branch_id uuid not null,ticket_id uuid not null references public.kitchen_tickets(id) on delete restrict,
 actor_user_id uuid references auth.users(id) on delete set null,station_id uuid references public.kitchen_stations(id) on delete set null,
 old_status text,new_status text not null,expected_version integer not null,source_event_id text not null,
 handover_receiver text,notes text,created_at timestamptz not null default now(),
 foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict,
 unique(tenant_id,source_event_id)
);
create table if not exists public.kitchen_sla_policies (
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete restrict,
 branch_id uuid not null,station_id uuid references public.kitchen_stations(id) on delete restrict,
 product_id uuid references public.products(id) on delete restrict,target_minutes integer not null check(target_minutes between 1 and 1440),
 escalation_after_minutes integer not null check(escalation_after_minutes>=target_minutes),
 is_active boolean not null default true,created_by uuid not null references auth.users(id) on delete restrict,
 foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict
);
create table if not exists public.kitchen_sla_escalations (
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete restrict,
 branch_id uuid not null,ticket_id uuid not null references public.kitchen_tickets(id) on delete restrict,
 stage text not null,elapsed_minutes integer not null,created_at timestamptz not null default now(),
 foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict,
 unique(ticket_id,stage)
);
create table if not exists public.inventory_uom_conversions (
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete restrict,
 inventory_item_id uuid not null references public.inventory_items(id) on delete restrict,
 from_unit text not null,to_unit text not null,factor numeric(18,8) not null check(factor>0),
 effective_from date not null,effective_to date,approved_by uuid not null references auth.users(id) on delete restrict,
 created_at timestamptz not null default now(),check(effective_to is null or effective_to>=effective_from),
 unique(tenant_id,inventory_item_id,from_unit,to_unit,effective_from)
);
create table if not exists public.inventory_item_costs (
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete restrict,
 inventory_item_id uuid not null references public.inventory_items(id) on delete restrict,
 cost_per_base_unit_idr bigint not null check(cost_per_base_unit_idr>=0),
 effective_from date not null,effective_to date,source_reference text not null,approved_by uuid not null references auth.users(id) on delete restrict,
 created_at timestamptz not null default now(),check(effective_to is null or effective_to>=effective_from)
);
create table if not exists public.production_prep_plans (
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete restrict,
 branch_id uuid not null,service_date date not null,shift_id uuid not null,demand_reference text not null,
 status text not null default 'planned' check(status in ('planned','reserved','released','completed','cancelled')),
 idempotency_key text not null,created_by uuid not null references auth.users(id) on delete restrict,
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict,
 unique(tenant_id,idempotency_key)
);
create table if not exists public.production_prep_plan_items (
 id uuid primary key default gen_random_uuid(),plan_id uuid not null references public.production_prep_plans(id) on delete cascade,
 product_id uuid not null references public.products(id) on delete restrict,recipe_id uuid not null references public.recipes(id) on delete restrict,
 recipe_version integer not null,planned_quantity numeric(14,3) not null check(planned_quantity>0),
 created_at timestamptz not null default now(),unique(plan_id,product_id)
);
create table if not exists public.production_prep_plan_reservations (
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete restrict,
 branch_id uuid not null,plan_item_id uuid not null references public.production_prep_plan_items(id) on delete cascade,
 inventory_item_id uuid not null references public.inventory_items(id) on delete restrict,
 planned_quantity numeric(14,3) not null check(planned_quantity>0),unit text not null,
 status text not null default 'reserved' check(status in ('reserved','released','consumed')),
 created_at timestamptz not null default now(),
 foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict
);
create table if not exists public.production_mode_policies (
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete restrict,
 branch_id uuid not null,product_id uuid not null references public.products(id) on delete restrict,
 mode text not null check(mode in ('made_to_order','batch')),min_batch_quantity numeric(14,3) not null default 1 check(min_batch_quantity>0),
 is_active boolean not null default true,updated_by uuid not null references auth.users(id) on delete restrict,
 updated_at timestamptz not null default now(),foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict,
 unique(tenant_id,branch_id,product_id)
);
create table if not exists public.production_jobs (
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete restrict,
 branch_id uuid not null,product_id uuid not null references public.products(id) on delete restrict,
 order_id uuid references public.orders(id) on delete restrict,quantity numeric(14,3) not null check(quantity>0),
 status text not null default 'queued' check(status in ('queued','in_progress','completed','cancelled')),
 idempotency_key text not null,created_by uuid not null references auth.users(id) on delete restrict,created_at timestamptz not null default now(),
 foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict,unique(tenant_id,idempotency_key)
);
create table if not exists public.production_batch_outputs (
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete restrict,
 branch_id uuid not null,batch_id uuid not null references public.production_batches(id) on delete restrict,
 product_id uuid not null references public.products(id) on delete restrict,available_quantity numeric(14,3) not null check(available_quantity>=0),
 reserved_quantity numeric(14,3) not null default 0 check(reserved_quantity>=0 and reserved_quantity<=available_quantity),
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict,unique(batch_id)
);

do $$ declare t text; begin
 foreach t in array array['kitchen_stations','kitchen_station_assignments','kitchen_station_product_categories','kitchen_ticket_station_assignments',
  'kitchen_ticket_events','kitchen_sla_policies','kitchen_sla_escalations','inventory_uom_conversions','inventory_item_costs',
  'production_prep_plans','production_prep_plan_items','production_prep_plan_reservations','production_mode_policies',
  'production_jobs','production_batch_outputs'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('alter table public.%I force row level security',t);
  execute format('drop policy if exists service_role_only on public.%I',t);
  execute format('create policy service_role_only on public.%I for all to service_role using(true) with check(true)',t);
  execute format('revoke all on public.%I from public,anon,authenticated',t);
  execute format('grant select,insert,update on public.%I to service_role',t);
 end loop;
end $$;

create or replace function public.list_kitchen_station_board(p_tenant_id uuid,p_branch_id uuid,p_actor_user_id uuid,p_station_id uuid)
returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v_rows jsonb;
begin
 if coalesce(auth.jwt()->>'role','')<>'service_role' then raise exception using errcode='42501',message='KDS_SERVICE_ROLE_REQUIRED';end if;
 if not public.pos_actor_can_access_branch(p_actor_user_id,p_tenant_id,p_branch_id) then raise exception using errcode='42501',message='KDS_BRANCH_SCOPE_DENIED';end if;
 select coalesce(jsonb_agg(jsonb_build_object('stationId',s.id,'code',s.code,'name',s.name,'tickets',
  (select coalesce(jsonb_agg(jsonb_build_object('ticketId',t.id,'ticketNumber',t.ticket_number,'status',t.status,'version',t.version,
   'priority',t.priority,'createdAt',t.created_at,'items',(select coalesce(jsonb_agg(to_jsonb(i)),'[]'::jsonb)
    from public.kitchen_ticket_items i join public.kitchen_ticket_station_assignments a on a.kitchen_ticket_item_id=i.id
    where i.kitchen_ticket_id=t.id and a.station_id=s.id)) order by t.priority desc,t.created_at),'[]'::jsonb)
   from public.kitchen_tickets t where t.branch_id=p_branch_id and t.status not in ('served','cancelled')
    and exists(select 1 from public.kitchen_ticket_station_assignments a join public.kitchen_ticket_items i on i.id=a.kitchen_ticket_item_id
     where a.station_id=s.id and i.kitchen_ticket_id=t.id)) order by s.priority,s.code),'[]'::jsonb) into v_rows
 from public.kitchen_stations s where s.tenant_id=p_tenant_id and s.branch_id=p_branch_id and s.is_active
  and (p_station_id is null or s.id=p_station_id)
  and exists(select 1 from public.kitchen_station_assignments a where a.station_id=s.id and a.user_id=p_actor_user_id and a.is_active);
 return jsonb_build_object('tenantId',p_tenant_id,'branchId',p_branch_id,'stations',v_rows);
end $$;
revoke all on function public.list_kitchen_station_board(uuid,uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.list_kitchen_station_board(uuid,uuid,uuid,uuid) to service_role;

create or replace function public.dispatch_kitchen_ticket_atomic(
 p_tenant_id uuid,p_branch_id uuid,p_actor_user_id uuid,p_source_type text,p_source_id uuid,p_idempotency_key text
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v_ticket public.kitchen_tickets%rowtype;v_item public.kitchen_ticket_items%rowtype;v_station public.kitchen_stations%rowtype;v_first uuid;v_count integer:=0;v_source_paid boolean;
begin
 if coalesce(auth.jwt()->>'role','')<>'service_role' then raise exception using errcode='42501',message='KDS_SERVICE_ROLE_REQUIRED';end if;
 if not public.pos_actor_can_access_branch(p_actor_user_id,p_tenant_id,p_branch_id) then raise exception using errcode='42501',message='KDS_BRANCH_SCOPE_DENIED';end if;
 if p_source_type='pos_sale' then
  select payment_status='paid' into v_source_paid from public.pos_sales where id=p_source_id and branch_id=p_branch_id;
  if not coalesce(v_source_paid,false) then raise exception 'kds_source_not_paid';end if;
  select * into v_ticket from public.kitchen_tickets where pos_sale_id=p_source_id for update;
 elsif p_source_type='online_order' then
  select payment_status='paid' into v_source_paid from public.orders where id=p_source_id and branch_id=p_branch_id;
  if not coalesce(v_source_paid,false) then raise exception 'kds_source_not_paid';end if;
  select * into v_ticket from public.kitchen_tickets where order_id=p_source_id for update;
 else raise exception 'kds_source_type_invalid';end if;
 if not found then raise exception 'kds_ticket_not_dispatched_by_source_trigger';end if;
 for v_item in select * from public.kitchen_ticket_items where kitchen_ticket_id=v_ticket.id order by product_id,id for update loop
  select s.* into v_station from public.kitchen_stations s
   left join public.kitchen_station_product_categories c on c.station_id=s.id
   left join public.products p on p.id=v_item.product_id
   where s.tenant_id=p_tenant_id and s.branch_id=p_branch_id and s.is_active
    and (c.product_category=p.category or s.is_default)
   order by case when c.product_category=p.category then 0 else 1 end,s.priority,s.code limit 1;
  if not found then raise exception 'kitchen_station_not_configured';end if;
  insert into public.kitchen_ticket_station_assignments(tenant_id,branch_id,kitchen_ticket_item_id,station_id)
  values(p_tenant_id,p_branch_id,v_item.id,v_station.id) on conflict(kitchen_ticket_item_id) do nothing;
  v_first:=coalesce(v_first,v_station.id);v_count:=v_count+1;
 end loop;
 insert into public.kitchen_ticket_events(tenant_id,branch_id,ticket_id,actor_user_id,station_id,old_status,new_status,expected_version,source_event_id,notes)
 values(p_tenant_id,p_branch_id,v_ticket.id,p_actor_user_id,v_first,v_ticket.status,v_ticket.status,v_ticket.version,p_idempotency_key,'station assignment')
 on conflict(tenant_id,source_event_id) do nothing;
 return jsonb_build_object('ticketId',v_ticket.id,'tenantId',p_tenant_id,'branchId',p_branch_id,'stationId',v_first,
  'items',(select coalesce(jsonb_agg(to_jsonb(i)),'[]'::jsonb) from public.kitchen_ticket_items i where i.kitchen_ticket_id=v_ticket.id),
  'assignedItemCount',v_count);
end $$;
revoke all on function public.dispatch_kitchen_ticket_atomic(uuid,uuid,uuid,text,uuid,text) from public,anon,authenticated;
grant execute on function public.dispatch_kitchen_ticket_atomic(uuid,uuid,uuid,text,uuid,text) to service_role;

create or replace function public.transition_kitchen_ticket_scoped(
 p_tenant_id uuid,p_branch_id uuid,p_actor_user_id uuid,p_ticket_id uuid,p_station_id uuid,p_next_status text,
 p_expected_version integer,p_handover_receiver text,p_notes text,p_idempotency_key text
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v public.kitchen_tickets%rowtype;v_event public.kitchen_ticket_events%rowtype;v_allowed boolean:=false;
begin
 if coalesce(auth.jwt()->>'role','')<>'service_role' then raise exception using errcode='42501',message='KDS_SERVICE_ROLE_REQUIRED';end if;
 if not public.pos_actor_can_access_branch(p_actor_user_id,p_tenant_id,p_branch_id) then raise exception using errcode='42501',message='KDS_BRANCH_SCOPE_DENIED';end if;
 if not exists(select 1 from public.kitchen_station_assignments where station_id=p_station_id and user_id=p_actor_user_id and is_active)
  then raise exception using errcode='42501',message='KDS_STATION_ASSIGNMENT_REQUIRED';end if;
 select * into v from public.kitchen_tickets where id=p_ticket_id and branch_id=p_branch_id for update;
 if not found then raise exception 'kitchen_ticket_not_found';end if;
 if v.version<>p_expected_version then raise exception using errcode='40001',message='KDS_STALE_VERSION';end if;
 if p_next_status='served' and length(btrim(coalesce(p_handover_receiver,'')))<2 then raise exception 'KDS_HANDOVER_ACK_REQUIRED';end if;
 v_allowed:=case v.status when 'queued' then p_next_status in ('accepted','cancelled','blocked')
  when 'accepted' then p_next_status in ('preparing','cancelled','blocked')
  when 'preparing' then p_next_status in ('ready','cancelled','blocked')
  when 'ready' then p_next_status in ('served','preparing')
  when 'blocked' then p_next_status in ('accepted','cancelled') else false end;
 if not v_allowed then raise exception 'kitchen_ticket_transition_invalid';end if;
 insert into public.kitchen_ticket_events(tenant_id,branch_id,ticket_id,actor_user_id,station_id,old_status,new_status,expected_version,source_event_id,handover_receiver,notes)
 values(p_tenant_id,p_branch_id,p_ticket_id,p_actor_user_id,p_station_id,v.status,p_next_status,v.version,p_idempotency_key,p_handover_receiver,left(p_notes,500))
 on conflict(tenant_id,source_event_id) do nothing returning * into v_event;
 if not found then return jsonb_build_object('ticketId',p_ticket_id,'tenantId',p_tenant_id,'branchId',p_branch_id,'status',v.status,'version',v.version,'eventId',v_event.id,'duplicate',true);end if;
 update public.kitchen_tickets set status=p_next_status,version=version+1,updated_at=now(),
  accepted_at=case when p_next_status='accepted' then now() else accepted_at end,
  started_at=case when p_next_status='preparing' and started_at is null then now() else started_at end,
  ready_at=case when p_next_status='ready' then now() else ready_at end,
  served_at=case when p_next_status='served' then now() else served_at end,
  cancelled_at=case when p_next_status='cancelled' then now() else cancelled_at end,
  notes=coalesce(nullif(left(trim(coalesce(p_notes,'')),500),''),notes)
 where id=p_ticket_id returning * into v;
 update public.kitchen_ticket_items set status=case when p_next_status='preparing' then 'preparing'
  when p_next_status='ready' then 'ready' when p_next_status='served' then 'served'
  when p_next_status='cancelled' then 'cancelled' else status end where kitchen_ticket_id=p_ticket_id;
 if v.order_id is not null then
  update public.orders set fulfillment_status=case p_next_status when 'accepted' then 'accepted' when 'preparing' then 'preparing'
   when 'ready' then 'ready' when 'served' then 'fulfilled' when 'cancelled' then 'cancelled' else fulfillment_status end,
   fulfilled_at=case when p_next_status='served' then now() else fulfilled_at end,version=version+1,updated_at=now()
  where id=v.order_id and payment_status='paid';
  insert into public.order_status_history(order_id,status_type,old_status,new_status,changed_by,note)
  values(v.order_id,'fulfillment',v.status,case p_next_status when 'served' then 'fulfilled' else p_next_status end,p_actor_user_id,left(coalesce(p_notes,'KDS update'),500));
 end if;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'kitchen_ticket_transition','kitchen_ticket',p_ticket_id::text,jsonb_build_object('branch_id',p_branch_id,'from',v.status,'to',p_next_status,'version',v.version));
 return jsonb_build_object('ticketId',v.id,'tenantId',p_tenant_id,'branchId',p_branch_id,'status',v.status,'version',v.version,'eventId',v_event.id,'handoverReceiver',p_handover_receiver);
end $$;
revoke all on function public.transition_kitchen_ticket_scoped(uuid,uuid,uuid,uuid,uuid,text,integer,text,text,text) from public,anon,authenticated;
grant execute on function public.transition_kitchen_ticket_scoped(uuid,uuid,uuid,uuid,uuid,text,integer,text,text,text) to service_role;

create or replace function public.evaluate_kitchen_prep_sla_atomic(p_tenant_id uuid,p_branch_id uuid,p_actor_user_id uuid,p_evaluated_at timestamptz,p_limit integer)
returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v_ticket record;v_policy record;v_elapsed integer;v_stage text;v_id uuid;v_tickets jsonb:='[]'::jsonb;v_escalations jsonb:='[]'::jsonb;v_count integer:=0;
begin
 if coalesce(auth.jwt()->>'role','')<>'service_role' then raise exception using errcode='42501',message='KDS_SERVICE_ROLE_REQUIRED';end if;
 if not public.pos_actor_can_access_branch(p_actor_user_id,p_tenant_id,p_branch_id) then raise exception using errcode='42501',message='KDS_BRANCH_SCOPE_DENIED';end if;
 for v_ticket in select t.id,t.status,t.created_at,t.started_at,a.station_id,i.product_id
  from public.kitchen_tickets t join public.kitchen_ticket_items i on i.kitchen_ticket_id=t.id
  join public.kitchen_ticket_station_assignments a on a.kitchen_ticket_item_id=i.id
  where t.branch_id=p_branch_id and t.status in ('queued','accepted','preparing')
  order by t.created_at limit p_limit loop
  select * into v_policy from public.kitchen_sla_policies p where p.tenant_id=p_tenant_id and p.branch_id=p_branch_id
   and p.is_active and (p.station_id=v_ticket.station_id or p.station_id is null)
   and (p.product_id=v_ticket.product_id or p.product_id is null)
   order by (p.product_id is not null)::int desc,(p.station_id is not null)::int desc limit 1;
  if not found then continue;end if;
  v_elapsed:=floor(extract(epoch from (p_evaluated_at-coalesce(v_ticket.started_at,v_ticket.created_at)))/60)::integer;
  v_stage:=case when v_elapsed>=v_policy.escalation_after_minutes then 'escalation'
   when v_elapsed>=v_policy.target_minutes then 'overdue' else null end;
  v_tickets:=v_tickets||jsonb_build_array(jsonb_build_object('ticketId',v_ticket.id,'elapsedMinutes',v_elapsed,'stage',v_stage));
  if v_stage is not null then
   insert into public.kitchen_sla_escalations(tenant_id,branch_id,ticket_id,stage,elapsed_minutes)
   values(p_tenant_id,p_branch_id,v_ticket.id,v_stage,v_elapsed) on conflict(ticket_id,stage) do nothing returning id into v_id;
   if v_id is not null then
    v_escalations:=v_escalations||jsonb_build_array(jsonb_build_object('ticketId',v_ticket.id,'escalationId',v_id,'created',true));
    insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
    values(p_actor_user_id,'kitchen_sla_'||v_stage,'kitchen_ticket',v_ticket.id::text,jsonb_build_object('elapsed_minutes',v_elapsed,'target_minutes',v_policy.target_minutes));
   end if;
  end if;
  v_count:=v_count+1;if v_count>=p_limit then exit;end if;
 end loop;
 return jsonb_build_object('tenantId',p_tenant_id,'branchId',p_branch_id,'tickets',v_tickets,'escalations',v_escalations);
end $$;
revoke all on function public.evaluate_kitchen_prep_sla_atomic(uuid,uuid,uuid,timestamptz,integer) from public,anon,authenticated;
grant execute on function public.evaluate_kitchen_prep_sla_atomic(uuid,uuid,uuid,timestamptz,integer) to service_role;

create or replace function public.calculate_recipe_yield_cost(
 p_tenant_id uuid,p_branch_id uuid,p_actor_user_id uuid,p_recipe_id uuid,p_recipe_version integer,p_desired_good_quantity numeric,p_waste_tolerance_percent numeric
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v_recipe public.recipes%rowtype;v_item record;v_qty numeric;v_cost bigint;v_total bigint:=0;v_rows jsonb:='[]'::jsonb;
begin
 if coalesce(auth.jwt()->>'role','')<>'service_role' then raise exception using errcode='42501',message='RECIPE_SERVICE_ROLE_REQUIRED';end if;
 if not public.pos_actor_can_access_branch(p_actor_user_id,p_tenant_id,p_branch_id) then raise exception using errcode='42501',message='RECIPE_BRANCH_SCOPE_DENIED';end if;
 if p_desired_good_quantity<=0 or p_waste_tolerance_percent<0 or p_waste_tolerance_percent>100 then raise exception 'invalid_recipe_yield_input';end if;
 select r.* into v_recipe from public.recipes r join public.products p on p.id=r.product_id
 where r.id=p_recipe_id and r.version=p_recipe_version and p.is_active and r.status in ('draft','active');
 if not found then raise exception 'recipe_version_not_found';end if;
 for v_item in select ri.inventory_item_id,ri.quantity_per_yield,ri.unit,ii.unit base_unit,
  (select c.factor from public.inventory_uom_conversions c where c.tenant_id=p_tenant_id and c.inventory_item_id=ri.inventory_item_id
   and c.from_unit=ri.unit and c.to_unit=ii.unit and c.effective_from<=current_date
   and (c.effective_to is null or c.effective_to>=current_date) order by c.effective_from desc limit 1) conversion_factor,
  (select c.cost_per_base_unit_idr from public.inventory_item_costs c where c.tenant_id=p_tenant_id and c.inventory_item_id=ri.inventory_item_id
   and c.effective_from<=current_date and (c.effective_to is null or c.effective_to>=current_date)
   order by c.effective_from desc limit 1) cost_per_base_unit
  from public.recipe_ingredients ri join public.inventory_items ii on ii.id=ri.inventory_item_id where ri.recipe_id=p_recipe_id
  order by ri.inventory_item_id loop
  if v_item.unit<>v_item.base_unit and v_item.conversion_factor is null then raise exception 'recipe_uom_conversion_missing';end if;
  if v_item.cost_per_base_unit is null then raise exception 'inventory_cost_snapshot_missing';end if;
  v_qty:=round(v_item.quantity_per_yield*p_desired_good_quantity/v_recipe.yield_quantity*coalesce(v_item.conversion_factor,1),3);
  v_cost:=round(v_qty*v_item.cost_per_base_unit)::bigint;v_total:=v_total+v_cost;
  v_rows:=v_rows||jsonb_build_array(jsonb_build_object('inventoryItemId',v_item.inventory_item_id,'quantity',v_qty,
   'unit',v_item.base_unit,'costIdr',v_cost,'wasteTolerancePercent',p_waste_tolerance_percent));
 end loop;
 return jsonb_build_object('recipeId',p_recipe_id,'recipeVersion',p_recipe_version,'expectedOutputQuantity',p_desired_good_quantity,
  'totalCostIdr',v_total,'ingredients',v_rows);
end $$;
revoke all on function public.calculate_recipe_yield_cost(uuid,uuid,uuid,uuid,integer,numeric,numeric) from public,anon,authenticated;
grant execute on function public.calculate_recipe_yield_cost(uuid,uuid,uuid,uuid,integer,numeric,numeric) to service_role;

create or replace function public.complete_production_batch_scoped(
 p_tenant_id uuid,p_branch_id uuid,p_batch_id uuid,p_actual_good_quantity numeric,p_waste_quantity numeric,p_actual_consumptions jsonb,p_actor_user_id uuid
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v_batch public.production_batches%rowtype;v_result jsonb;v_rows jsonb;v_bad integer;
begin
 if coalesce(auth.jwt()->>'role','')<>'service_role' then raise exception using errcode='42501',message='PRODUCTION_SERVICE_ROLE_REQUIRED';end if;
 if not public.pos_actor_can_access_branch(p_actor_user_id,p_tenant_id,p_branch_id) then raise exception using errcode='42501',message='PRODUCTION_BRANCH_SCOPE_DENIED';end if;
 select * into v_batch from public.production_batches where id=p_batch_id and branch_id=p_branch_id for update;
 if not found then raise exception 'production_batch_not_found';end if;
 v_result:=public.erp_complete_production_batch(p_batch_id,p_actual_good_quantity,p_waste_quantity,p_actual_consumptions,p_actor_user_id);
 select count(*) filter(where pc.actual_quantity<>sm.quantity)::integer,
  coalesce(jsonb_agg(jsonb_build_object('inventoryItemId',pc.inventory_item_id,'actualQuantity',pc.actual_quantity,'stockMovementQuantity',sm.quantity,'stockMovementId',sm.id)),'[]'::jsonb)
 into v_bad,v_rows from public.production_consumptions pc join public.stock_movements sm on sm.id=pc.stock_movement_id
 where pc.batch_id=p_batch_id;
 if coalesce(v_bad,0)>0 then raise exception 'production_stock_ledger_mismatch';end if;
 return jsonb_build_object('ok',true,'status','completed','batchId',p_batch_id,'tenantId',p_tenant_id,'branchId',p_branch_id,
  'consumptions',v_rows,'consumptionCount',jsonb_array_length(v_rows));
end $$;
revoke all on function public.complete_production_batch_scoped(uuid,uuid,uuid,numeric,numeric,jsonb,uuid) from public,anon,authenticated;
grant execute on function public.complete_production_batch_scoped(uuid,uuid,uuid,numeric,numeric,jsonb,uuid) to service_role;

rollback;