-- DESIGN DRAFT ONLY — NOT A MIGRATION.
-- Existing suppliers are global and have no tenant_id. This bridge makes ownership explicit.
-- A supplier may be shared only through an explicit reviewed tenant link; no implicit global access.
create table if not exists public.supplier_tenant_links (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete restrict,
 supplier_id uuid not null references public.suppliers(id) on delete restrict,
 status text not null default 'pending' check(status in ('pending','active','suspended','revoked')),
 relationship_type text not null default 'exclusive' check(relationship_type in ('exclusive','shared')),
 approved_by uuid null references auth.users(id) on delete restrict,
 approved_at timestamptz null,
 created_by uuid not null references auth.users(id) on delete restrict,
 created_at timestamptz not null default now(),
 unique(tenant_id,id),
 unique(tenant_id,supplier_id),
 check(status<>'active' or (approved_by is not null and approved_at is not null))
);
create table if not exists public.procurement_supplier_invoices (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete restrict,
 branch_id uuid not null,
 supplier_id uuid not null references public.suppliers(id) on delete restrict,
 purchase_order_id uuid not null references public.purchase_orders(id) on delete restrict,
 supplier_invoice_number text not null,
 invoice_date date not null,
 due_date date null,
 currency text not null default 'IDR' check(currency='IDR'),
 subtotal_idr bigint not null check(subtotal_idr>=0),
 tax_idr bigint not null default 0 check(tax_idr>=0),
 total_idr bigint generated always as (subtotal_idr+tax_idr) stored,
 status text not null default 'received' check(status in ('received','matching','matched','disputed','approved','posted','paid','void')),
 attachment_object_path text not null,
 idempotency_key text not null,
 received_by uuid not null references auth.users(id) on delete restrict,
 approved_by uuid null references auth.users(id) on delete restrict,
 posted_at timestamptz null,
 created_at timestamptz not null default now(),
 unique(tenant_id,id),
 unique(tenant_id,supplier_id,supplier_invoice_number),
 unique(tenant_id,idempotency_key),
 foreign key(tenant_id,branch_id) references public.branches(tenant_id,id) on delete restrict,
 check(due_date is null or due_date>=invoice_date),
 check(status not in ('approved','posted','paid') or approved_by is not null),
 check(status<>'posted' or posted_at is not null)
);
create table if not exists public.procurement_invoice_match_lines (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete restrict,
 invoice_id uuid not null,
 purchase_order_item_id uuid not null references public.purchase_order_items(id) on delete restrict,
 receipt_item_id uuid not null references public.purchase_receipt_items(id) on delete restrict,
 invoiced_quantity numeric(14,3) not null check(invoiced_quantity>0),
 invoiced_unit_cost_idr bigint not null check(invoiced_unit_cost_idr>=0),
 received_quantity numeric(14,3) not null check(received_quantity>=0),
 ordered_quantity numeric(14,3) not null check(ordered_quantity>=0),
 quantity_variance numeric(14,3) generated always as (invoiced_quantity-received_quantity) stored,
 unit_cost_variance_idr bigint not null,
 match_status text not null check(match_status in ('matched','quantity_variance','price_variance','rejected')),
 reviewed_by uuid null references auth.users(id) on delete restrict,
 reviewed_at timestamptz null,
 created_at timestamptz not null default now(),
 foreign key(tenant_id,invoice_id) references public.procurement_supplier_invoices(tenant_id,id) on delete restrict,
 unique(tenant_id,id)
);
create index if not exists procurement_supplier_invoice_period_idx on public.procurement_supplier_invoices(tenant_id,branch_id,invoice_date,status);
create or replace function public.procurement_match_supplier_invoice(
 p_invoice_id uuid,p_lines jsonb,p_tolerance_idr bigint,p_actor_user_id uuid
) returns jsonb language plpgsql security invoker set search_path=''
as $
declare v_invoice public.procurement_supplier_invoices%rowtype; v_line jsonb;
 v_po_item public.purchase_order_items%rowtype; v_receipt_item public.purchase_receipt_items%rowtype;
 v_received_po uuid; v_total_invoiced numeric:=0; v_total_received numeric:=0;
 v_all_match boolean:=true; v_count integer:=0; v_invoice_qty numeric; v_invoice_cost bigint;
 v_variance bigint; v_status text;
begin
 if p_tolerance_idr<0 or jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)=0 then
  raise exception using errcode='22023',message='INVALID_INVOICE_MATCH_INPUT';
 end if;
 select * into v_invoice from public.procurement_supplier_invoices where id=p_invoice_id for update;
 if not found then raise exception using errcode='P0002',message='SUPPLIER_INVOICE_NOT_FOUND'; end if;
 if v_invoice.status not in ('received','matching') then raise exception using errcode='23514',message='SUPPLIER_INVOICE_NOT_MATCHABLE'; end if;
 if not exists(select 1 from public.purchase_orders po join public.branches b on b.id=po.branch_id
   where po.id=v_invoice.purchase_order_id and po.supplier_id=v_invoice.supplier_id
    and po.branch_id=v_invoice.branch_id and b.tenant_id=v_invoice.tenant_id) then
  raise exception using errcode='42501',message='PURCHASE_ORDER_TENANT_OR_SUPPLIER_MISMATCH';
 end if;
 if not exists(select 1 from public.supplier_tenant_links l where l.tenant_id=v_invoice.tenant_id and l.supplier_id=v_invoice.supplier_id and l.status='active') then
  raise exception using errcode='42501',message='SUPPLIER_NOT_LINKED_TO_TENANT';
 end if;
 delete from public.procurement_invoice_match_lines where tenant_id=v_invoice.tenant_id and invoice_id=v_invoice.id;
 for v_line in select value from jsonb_array_elements(p_lines) loop
  select * into v_po_item from public.purchase_order_items where id=(v_line->>'purchase_order_item_id')::uuid and purchase_order_id=v_invoice.purchase_order_id;
  if not found then raise exception using errcode='23514',message='PO_ITEM_MISMATCH'; end if;
  select ri.* into v_receipt_item from public.purchase_receipt_items ri
   join public.purchase_receipts r on r.id=ri.receipt_id
   where ri.id=(v_line->>'receipt_item_id')::uuid and ri.purchase_order_item_id=v_po_item.id
    and r.purchase_order_id=v_invoice.purchase_order_id and r.branch_id=v_invoice.branch_id and r.status in ('received','reconciled');
  if not found then raise exception using errcode='23514',message='ACCEPTED_RECEIPT_ITEM_REQUIRED'; end if;
  v_invoice_qty:=(v_line->>'invoiced_quantity')::numeric;
  v_invoice_cost:=(v_line->>'invoiced_unit_cost_idr')::bigint;
  if v_invoice_qty<=0 or v_invoice_cost<0 then raise exception using errcode='22023',message='INVALID_INVOICE_LINE'; end if;
  v_variance:=v_invoice_cost-v_po_item.unit_cost_idr;
  insert into public.procurement_invoice_match_lines
   (tenant_id,invoice_id,purchase_order_item_id,receipt_item_id,invoiced_quantity,invoiced_unit_cost_idr,
    received_quantity,ordered_quantity,unit_cost_variance_idr,match_status)
  values(v_invoice.tenant_id,v_invoice.id,v_po_item.id,v_receipt_item.id,v_invoice_qty,v_invoice_cost,
    v_receipt_item.quantity_received,v_po_item.quantity,v_variance,
    case when v_invoice_qty<=v_receipt_item.quantity_received and abs(v_variance)<=p_tolerance_idr then 'matched'
      when v_invoice_qty>v_receipt_item.quantity_received then 'quantity_variance' else 'price_variance' end);
  if v_invoice_qty>v_receipt_item.quantity_received or abs(v_variance)>p_tolerance_idr then v_all_match:=false; end if;
  v_total_invoiced:=v_total_invoiced+(v_invoice_qty*v_invoice_cost);
  v_total_received:=v_total_received+(least(v_invoice_qty,v_receipt_item.quantity_received)*v_po_item.unit_cost_idr);
  v_count:=v_count+1;
 end loop;
 v_status:=case when v_all_match and abs(round(v_total_invoiced)-v_invoice.subtotal_idr)<=p_tolerance_idr then 'matched' else 'disputed' end;
 update public.procurement_supplier_invoices set status=v_status where id=v_invoice.id;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'procurement.supplier_invoice.'||v_status,'procurement_supplier_invoice',v_invoice.id::text,
  jsonb_build_object('tenant_id',v_invoice.tenant_id,'purchase_order_id',v_invoice.purchase_order_id,'line_count',v_count,
   'invoiced_subtotal_idr',round(v_total_invoiced),'po_received_value_idr',round(v_total_received),'tolerance_idr',p_tolerance_idr));
 return jsonb_build_object('invoice_id',v_invoice.id,'status',v_status,'line_count',v_count,
  'invoiced_subtotal_idr',round(v_total_invoiced),'po_received_value_idr',round(v_total_received));
end $;
revoke all on function public.procurement_match_supplier_invoice(uuid,jsonb,bigint,uuid) from public,anon,authenticated;
grant execute on function public.procurement_match_supplier_invoice(uuid,jsonb,bigint,uuid) to service_role;

create table if not exists public.procurement_approval_events (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete restrict,
 entity_type text not null check(entity_type in ('requisition','purchase_order','supplier_invoice')),
 entity_id uuid not null,
 event_type text not null check(event_type in ('submitted','approved','rejected','returned','posted')),
 actor_user_id uuid not null references auth.users(id) on delete restrict,
 reason text null,
 created_at timestamptz not null default now()
);
create index if not exists procurement_approval_entity_idx on public.procurement_approval_events(tenant_id,entity_type,entity_id,created_at);
do $$
declare t text;
begin foreach t in array array['supplier_tenant_links','procurement_supplier_invoices','procurement_invoice_match_lines','procurement_approval_events'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('drop policy if exists service_role_only on public.%I',t);
 execute format('create policy service_role_only on public.%I for all to service_role using(true) with check(true)',t);
 execute format('revoke all on public.%I from anon,authenticated',t);
 execute format('grant select,insert,update,delete on public.%I to service_role',t);
end loop; end $$;
create or replace function public.procurement_approve_supplier_link(p_link_id uuid,p_actor_user_id uuid)
returns jsonb language plpgsql security invoker set search_path=''
as $
declare v public.supplier_tenant_links%rowtype;
begin
 select * into v from public.supplier_tenant_links where id=p_link_id for update;
 if not found then raise exception using errcode='P0002',message='SUPPLIER_LINK_NOT_FOUND'; end if;
 if v.status<>'pending' then raise exception using errcode='23514',message='SUPPLIER_LINK_NOT_PENDING'; end if;
 if v.created_by=p_actor_user_id then raise exception using errcode='42501',message='INDEPENDENT_SUPPLIER_APPROVER_REQUIRED'; end if;
 update public.supplier_tenant_links set status='active',approved_by=p_actor_user_id,approved_at=now() where id=p_link_id returning * into v;
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'procurement.supplier_link.approved','supplier_tenant_link',v.id::text,
 jsonb_build_object('tenant_id',v.tenant_id,'supplier_id',v.supplier_id,'relationship_type',v.relationship_type,'created_by',v.created_by));
 return jsonb_build_object('link_id',v.id,'status',v.status);
end $;
revoke all on function public.procurement_approve_supplier_link(uuid,uuid) from public,anon,authenticated;
grant execute on function public.procurement_approve_supplier_link(uuid,uuid) to service_role;

-- Three-way matching must compare invoice lines to PO quantities/prices and accepted GRN lines.
-- Posting must be a single balanced Finance AP journal transaction with invoice reference.
-- Do not update suppliers directly from tenant-scoped endpoints until supplier_tenant_links is active.


-- Invoice approval is separate from receiving and three-way matching.
-- Only a fully matched invoice can be approved, and the receiver/matcher
-- cannot approve their own invoice. Payment/posting is intentionally separate.
create or replace function public.procurement_approve_supplier_invoice(
 p_invoice_id uuid,p_actor_user_id uuid,p_reason text
) returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v public.procurement_supplier_invoices%rowtype; v_line_count integer; v_bad_count integer;
begin
 select * into v from public.procurement_supplier_invoices where id=p_invoice_id for update;
 if not found then raise exception using errcode='P0002',message='SUPPLIER_INVOICE_NOT_FOUND'; end if;
 if v.status<>'matched' then raise exception using errcode='23514',message='ONLY_MATCHED_INVOICE_CAN_BE_APPROVED'; end if;
 if v.received_by=p_actor_user_id then raise exception using errcode='42501',message='INDEPENDENT_INVOICE_APPROVER_REQUIRED'; end if;
 if length(btrim(coalesce(p_reason,'')))<3 then raise exception using errcode='22023',message='INVOICE_APPROVAL_REASON_REQUIRED'; end if;
 select count(*),count(*) filter(where match_status<>'matched')
 into v_line_count,v_bad_count from public.procurement_invoice_match_lines
 where tenant_id=v.tenant_id and invoice_id=v.id;
 if v_line_count=0 or v_bad_count>0 then raise exception using errcode='23514',message='THREE_WAY_MATCH_NOT_CLEAN'; end if;
 update public.procurement_supplier_invoices set status='approved',approved_by=p_actor_user_id where id=v.id;
 insert into public.procurement_approval_events(tenant_id,entity_type,entity_id,event_type,actor_user_id,reason)
 values(v.tenant_id,'supplier_invoice',v.id,'approved',p_actor_user_id,left(p_reason,500));
 insert into public.admin_audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(p_actor_user_id,'procurement.supplier_invoice.approved','procurement_supplier_invoice',v.id::text,
  jsonb_build_object('tenant_id',v.tenant_id,'branch_id',v.branch_id,'purchase_order_id',v.purchase_order_id,'supplier_id',v.supplier_id,'line_count',v_line_count,'total_idr',v.total_idr,'received_by',v.received_by));
 return jsonb_build_object('invoice_id',v.id,'status','approved','approved_by',p_actor_user_id,'line_count',v_line_count,'total_idr',v.total_idr);
end $$;
revoke all on function public.procurement_approve_supplier_invoice(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.procurement_approve_supplier_invoice(uuid,uuid,text) to service_role;
