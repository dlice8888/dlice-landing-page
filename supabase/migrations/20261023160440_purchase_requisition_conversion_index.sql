-- Cover the FK used to link a converted requisition to its generated purchase order.
create index if not exists purchase_requisitions_converted_po_idx
  on public.purchase_requisitions(converted_purchase_order_id)
  where converted_purchase_order_id is not null;
