BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(35);

-- All tenant-sensitive business tables must have RLS enabled.
SELECT ok(
  (SELECT c.relrowsecurity
   FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='public' AND c.relname=t.table_name),
  format('%s has row-level security enabled',t.table_name)
)
FROM (VALUES
    ('tenant_memberships'),
    ('branches'),
    ('branch_assignments'),
    ('branch_inventory'),
    ('stock_movements'),
    ('orders'),
    ('order_items'),
    ('order_reservations'),
    ('payment_records'),
    ('purchase_orders'),
    ('purchase_receipts'),
    ('production_batches'),
    ('finance_journal_entries'),
    ('pos_sales'),
    ('pos_shifts'),
    ('admin_profiles'),
    ('admin_audit_logs')
) AS t(table_name);

-- No permissive policy may grant anon/authenticated/public direct access.
-- Existing deny_direct_client_access policies are valid only when both USING
-- and WITH CHECK are false. service_role_only tables have no client policy.
SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM pg_policies p
    WHERE p.schemaname='public'
      AND p.tablename=t.table_name
      AND (
        p.roles @> ARRAY['public']::name[]
        OR p.roles @> ARRAY['anon']::name[]
        OR p.roles @> ARRAY['authenticated']::name[]
      )
      AND (
        p.qual IS DISTINCT FROM 'false'
        OR p.with_check IS DISTINCT FROM 'false'
      )
  ),
  format('%s has no permissive direct-client policy',t.table_name)
)
FROM (VALUES
    ('tenant_memberships'),
    ('branches'),
    ('branch_assignments'),
    ('branch_inventory'),
    ('stock_movements'),
    ('orders'),
    ('order_items'),
    ('order_reservations'),
    ('payment_records'),
    ('purchase_orders'),
    ('purchase_receipts'),
    ('production_batches'),
    ('finance_journal_entries'),
    ('pos_sales'),
    ('pos_shifts'),
    ('admin_profiles'),
    ('admin_audit_logs')
) AS t(table_name);

SELECT is(
  (SELECT count(*)::integer
   FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='public' AND c.relkind='r' AND NOT c.relrowsecurity),
  0,
  'no public table is missing RLS'
);

SELECT * FROM finish();
ROLLBACK;
