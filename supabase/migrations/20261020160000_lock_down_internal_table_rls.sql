-- Restrict sensitive operational tables to the Edge Function's service_role.
-- RLS stays enabled. No anon/authenticated/PUBLIC policies are created.
-- The service_role-only policies are explicit documentation for the security
-- advisor and defense-in-depth; service_role retains its existing grants.
-- Do not use these tables directly from browser clients.

REVOKE ALL PRIVILEGES ON TABLE
  public.admin_audit_logs,
  public.admin_profiles,
  public.funnel_daily_metrics,
  public.notification_log,
  public.order_items,
  public.order_reservations,
  public.order_status_history,
  public.orders,
  public.payment_records,
  public.payment_settings,
  public.product_capacity,
  public.request_rate_limits
FROM PUBLIC, anon, authenticated;

CREATE POLICY service_role_only ON public.admin_audit_logs
  FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE POLICY service_role_only ON public.admin_profiles
  FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE POLICY service_role_only ON public.funnel_daily_metrics
  FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE POLICY service_role_only ON public.notification_log
  FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE POLICY service_role_only ON public.order_items
  FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE POLICY service_role_only ON public.order_reservations
  FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE POLICY service_role_only ON public.order_status_history
  FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE POLICY service_role_only ON public.orders
  FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE POLICY service_role_only ON public.payment_records
  FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE POLICY service_role_only ON public.payment_settings
  FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE POLICY service_role_only ON public.product_capacity
  FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE POLICY service_role_only ON public.request_rate_limits
  FOR ALL TO service_role USING (true) WITH CHECK (true);

COMMENT ON POLICY service_role_only ON public.admin_audit_logs IS 'Sensitive internal table: service_role only; no browser-role access.';
COMMENT ON POLICY service_role_only ON public.admin_profiles IS 'Sensitive internal table: service_role only; no browser-role access.';
COMMENT ON POLICY service_role_only ON public.funnel_daily_metrics IS 'Internal privacy-preserving aggregates: service_role only.';
COMMENT ON POLICY service_role_only ON public.notification_log IS 'Internal notification records: service_role only.';
COMMENT ON POLICY service_role_only ON public.order_items IS 'Order line items are accessed only by the trusted Edge Function.';
COMMENT ON POLICY service_role_only ON public.order_reservations IS 'Capacity reservations are managed only by trusted server operations.';
COMMENT ON POLICY service_role_only ON public.order_status_history IS 'Order status history is accessed only by trusted server operations.';
COMMENT ON POLICY service_role_only ON public.orders IS 'Customer/order records are accessed only through the trusted Edge Function.';
COMMENT ON POLICY service_role_only ON public.payment_records IS 'Payment proof and verification records are server-only.';
COMMENT ON POLICY service_role_only ON public.payment_settings IS 'Payment settings are server-only.';
COMMENT ON POLICY service_role_only ON public.product_capacity IS 'Capacity controls are managed only by trusted server operations.';
COMMENT ON POLICY service_role_only ON public.request_rate_limits IS 'Rate-limit counters are server-only.';
