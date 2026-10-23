-- Applied to staging as migration 20261020202805.
drop trigger if exists trg_erp_guard_refund_amount on public.refund_records;
create trigger trg_erp_guard_refund_amount before insert or update on public.refund_records for each row execute function public.erp_guard_refund_amount();
