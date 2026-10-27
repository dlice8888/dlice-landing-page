-- POS sale rows are inserted before their line items in erp_create_pos_sale().
-- Defer KDS dispatch until transaction commit so the ticket snapshots every line, modifier and substitution.
drop trigger if exists dlice_kitchen_ticket_from_pos_sale on public.pos_sales;
create constraint trigger dlice_kitchen_ticket_from_pos_sale
after insert on public.pos_sales
deferrable initially deferred
for each row execute function public.dlice_dispatch_kitchen_ticket();
