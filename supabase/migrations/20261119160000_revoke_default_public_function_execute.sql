-- Prevent future public-schema RPCs from inheriting client EXECUTE by default.
-- Edge Functions use service_role; direct client access remains denied by RLS and action-level authorization.
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon, authenticated;

-- All browser-facing calls are routed through dlice-orders with its service-role client.
-- Remove direct PostgREST RPC execution from every existing public-schema function.
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO service_role;

-- Keep the trigger-only boundary explicit for the historically exposed functions.
REVOKE EXECUTE ON FUNCTION public.erp_guard_journal_period() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.erp_guard_refund_amount() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.set_updated_at() FROM PUBLIC, anon, authenticated;
