-- Trigger-only guard/maintenance functions must not be callable through PostgREST RPC.
-- Existing PostgreSQL triggers can continue to invoke their trigger functions after
-- EXECUTE is revoked from API roles; this does not change application table policies.
REVOKE EXECUTE ON FUNCTION public.erp_guard_journal_period() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.erp_guard_refund_amount() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.set_updated_at() FROM PUBLIC, anon, authenticated;
