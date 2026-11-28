-- D02-F06 payment-method expansion design draft (NOT an official migration).
-- Grounded in the dlice-staging schema inspected read-only on 2026-11-29.
-- Do not apply until RPC allowlists, provider references, webhook replay protection,
-- settlement matching, refunds, and rollback have been reviewed together.
--
-- Current staging checks:
-- pos_sales_payment_method_check: cash, bank_transfer, qris, split
-- pos_sale_tenders_payment_method_check: cash, bank_transfer, qris
-- payment_records_method_check: bank_transfer, dlice_qris
-- payment_settlements_payment_method_check: bank_transfer, qris
--
-- The following constraint changes are only one part of the rollout. The server
-- RPCs that create sales/intents/tenders and reconcile provider settlements must
-- be updated in the same reviewed migration before card is enabled in staging.

alter table public.pos_sales
 drop constraint if exists pos_sales_payment_method_check;
alter table public.pos_sales
 add constraint pos_sales_payment_method_check
 check (payment_method = any (array['cash','bank_transfer','qris','card','split']::text[]));

alter table public.pos_sale_tenders
 drop constraint if exists pos_sale_tenders_payment_method_check;
alter table public.pos_sale_tenders
 add constraint pos_sale_tenders_payment_method_check
 check (payment_method = any (array['cash','bank_transfer','qris','card']::text[]));

alter table public.payment_records
 drop constraint if exists payment_records_method_check;
alter table public.payment_records
 add constraint payment_records_method_check
 check (method = any (array['bank_transfer','dlice_qris','card']::text[]));

alter table public.payment_settlements
 drop constraint if exists payment_settlements_payment_method_check;
alter table public.payment_settlements
 add constraint payment_settlements_payment_method_check
 check (payment_method = any (array['bank_transfer','qris','card']::text[]));

-- Acceptance requirements before promotion:
-- 1. Every card payment intent must reference an enabled provider/terminal config.
-- 2. Only signed, timestamp-bounded, idempotent provider events can confirm paid.
-- 3. Tender allocations must equal sale total; over/underpayment must roll back.
-- 4. Settlement provider reference and fee/net amounts must reconcile per tender.
-- 5. Refund reversal must retain original tender method and provider reference.
-- 6. RLS, function EXECUTE ACLs, tenant/branch composite FKs and rollback must pass.
-- 7. Do not enable card UI in production before authenticated staging E6 passes.
