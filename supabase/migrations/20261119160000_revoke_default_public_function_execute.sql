-- Prevent future public-schema RPCs from inheriting client EXECUTE by default.
-- Edge Functions use service_role; direct client access remains denied by RLS and action-level authorization.
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon, authenticated;

-- Reassert the trigger-only ACL boundary against the live staging catalog.
REVOKE EXECUTE ON FUNCTION public.erp_guard_journal_period() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.erp_guard_refund_amount() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.set_updated_at() FROM PUBLIC, anon, authenticated;
