-- Explicitly deny direct Data API access to operational/ERP tables.
-- These tables are accessed through the authenticated Edge Function using
-- the server-side service role; anon/authenticated have no direct table grants.
-- Restrictive policies preserve deny-by-default even if a permissive policy is
-- accidentally added later. Do not grant direct client access without a reviewed
-- per-role and per-branch authorization design.

DO $migration$
DECLARE
  table_name text;
  target_tables text[] := ARRAY[
    'branch_assignments',
    'branch_expenses',
    'branch_inventory',
    'branch_product_capacity',
    'branches',
    'cash_reconciliations',
    'finance_journal_entries',
    'fiscal_periods',
    'inventory_items',
    'job_positions',
    'payment_settlement_items',
    'payment_settlements',
    'pos_sale_items',
    'pos_sales',
    'pos_shifts',
    'production_batches',
    'production_consumptions',
    'purchase_order_items',
    'purchase_orders',
    'purchase_receipt_items',
    'purchase_receipts',
    'recipe_ingredients',
    'recipes',
    'refund_records',
    'stock_movements',
    'suppliers',
    'tax_settings'
  ];
BEGIN
  FOREACH table_name IN ARRAY target_tables LOOP
    IF to_regclass(format('public.%I', table_name)) IS NULL THEN
      RAISE EXCEPTION 'Expected internal table public.% is missing; aborting migration', table_name;
    END IF;

    IF NOT EXISTS (
      SELECT 1
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public'
        AND c.relname = table_name
        AND c.relrowsecurity
    ) THEN
      RAISE EXCEPTION 'RLS is not enabled on public.%; aborting migration', table_name;
    END IF;

    IF NOT EXISTS (
      SELECT 1
      FROM pg_policies p
      WHERE p.schemaname = 'public'
        AND p.tablename = table_name
        AND p.policyname = 'deny_direct_client_access'
    ) THEN
      EXECUTE format(
        'CREATE POLICY %I ON public.%I AS RESTRICTIVE FOR ALL TO anon, authenticated USING (false) WITH CHECK (false)',
        'deny_direct_client_access',
        table_name
      );
    END IF;
  END LOOP;
END
$migration$;
