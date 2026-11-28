-- Remove an unintended direct EXECUTE grant on an immutable receipt trigger.
-- PostgreSQL invokes trigger functions through their trigger bindings; API roles
-- do not need direct EXECUTE privilege on this trigger function.
REVOKE ALL ON FUNCTION public.prevent_pos_sale_receipt_mutation()
  FROM PUBLIC, anon, authenticated, service_role;
