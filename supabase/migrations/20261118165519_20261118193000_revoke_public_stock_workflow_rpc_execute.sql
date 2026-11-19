-- The stock workflow RPCs are called only by the trusted dlice-orders Edge Function
-- using its service-role Supabase client after per-action identity, permission,
-- active-membership, and branch-scope checks.
-- Remove PostgreSQL's default PUBLIC EXECUTE and any explicit client-role grants.
REVOKE ALL ON FUNCTION public.erp_create_stock_count(text, uuid, jsonb, uuid, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.erp_create_stock_count(text, uuid, jsonb, uuid, text, text) TO service_role;

REVOKE ALL ON FUNCTION public.erp_create_stock_transfer(text, uuid, uuid, jsonb, uuid, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.erp_create_stock_transfer(text, uuid, uuid, jsonb, uuid, text, text) TO service_role;

REVOKE ALL ON FUNCTION public.erp_post_stock_count(uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.erp_post_stock_count(uuid, uuid) TO service_role;

REVOKE ALL ON FUNCTION public.erp_transition_stock_transfer(uuid, uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.erp_transition_stock_transfer(uuid, uuid, text) TO service_role;

REVOKE ALL ON FUNCTION public.erp_update_stock_count_item(uuid, uuid, numeric) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.erp_update_stock_count_item(uuid, uuid, numeric) TO service_role;
