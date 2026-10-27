-- Explicitly deny direct client access to server-only ERP/platform tables.
-- Trusted Edge Function operations use service_role and are not affected by these policies.
-- This migration is staging-first; verify every action through the server-side authorization layer.

alter table public.backup_restore_runs enable row level security;
revoke all on table public.backup_restore_runs from anon, authenticated;
drop policy if exists deny_direct_client_access on public.backup_restore_runs;
create policy deny_direct_client_access on public.backup_restore_runs
  for all to anon, authenticated
  using (false)
  with check (false);

alter table public.branch_settings enable row level security;
revoke all on table public.branch_settings from anon, authenticated;
drop policy if exists deny_direct_client_access on public.branch_settings;
create policy deny_direct_client_access on public.branch_settings
  for all to anon, authenticated
  using (false)
  with check (false);

alter table public.integration_connections enable row level security;
revoke all on table public.integration_connections from anon, authenticated;
drop policy if exists deny_direct_client_access on public.integration_connections;
create policy deny_direct_client_access on public.integration_connections
  for all to anon, authenticated
  using (false)
  with check (false);

alter table public.integration_outbox enable row level security;
revoke all on table public.integration_outbox from anon, authenticated;
drop policy if exists deny_direct_client_access on public.integration_outbox;
create policy deny_direct_client_access on public.integration_outbox
  for all to anon, authenticated
  using (false)
  with check (false);

alter table public.inventory_waste_events enable row level security;
revoke all on table public.inventory_waste_events from anon, authenticated;
drop policy if exists deny_direct_client_access on public.inventory_waste_events;
create policy deny_direct_client_access on public.inventory_waste_events
  for all to anon, authenticated
  using (false)
  with check (false);

alter table public.kitchen_ticket_items enable row level security;
revoke all on table public.kitchen_ticket_items from anon, authenticated;
drop policy if exists deny_direct_client_access on public.kitchen_ticket_items;
create policy deny_direct_client_access on public.kitchen_ticket_items
  for all to anon, authenticated
  using (false)
  with check (false);

alter table public.kitchen_tickets enable row level security;
revoke all on table public.kitchen_tickets from anon, authenticated;
drop policy if exists deny_direct_client_access on public.kitchen_tickets;
create policy deny_direct_client_access on public.kitchen_tickets
  for all to anon, authenticated
  using (false)
  with check (false);

alter table public.offline_sync_receipts enable row level security;
revoke all on table public.offline_sync_receipts from anon, authenticated;
drop policy if exists deny_direct_client_access on public.offline_sync_receipts;
create policy deny_direct_client_access on public.offline_sync_receipts
  for all to anon, authenticated
  using (false)
  with check (false);

alter table public.order_stock_consumptions enable row level security;
revoke all on table public.order_stock_consumptions from anon, authenticated;
drop policy if exists deny_direct_client_access on public.order_stock_consumptions;
create policy deny_direct_client_access on public.order_stock_consumptions
  for all to anon, authenticated
  using (false)
  with check (false);

alter table public.pos_idempotency_requests enable row level security;
revoke all on table public.pos_idempotency_requests from anon, authenticated;
drop policy if exists deny_direct_client_access on public.pos_idempotency_requests;
create policy deny_direct_client_access on public.pos_idempotency_requests
  for all to anon, authenticated
  using (false)
  with check (false);

alter table public.product_modifiers enable row level security;
revoke all on table public.product_modifiers from anon, authenticated;
drop policy if exists deny_direct_client_access on public.product_modifiers;
create policy deny_direct_client_access on public.product_modifiers
  for all to anon, authenticated
  using (false)
  with check (false);

alter table public.recipe_substitutions enable row level security;
revoke all on table public.recipe_substitutions from anon, authenticated;
drop policy if exists deny_direct_client_access on public.recipe_substitutions;
create policy deny_direct_client_access on public.recipe_substitutions
  for all to anon, authenticated
  using (false)
  with check (false);

alter table public.shift_handover_records enable row level security;
revoke all on table public.shift_handover_records from anon, authenticated;
drop policy if exists deny_direct_client_access on public.shift_handover_records;
create policy deny_direct_client_access on public.shift_handover_records
  for all to anon, authenticated
  using (false)
  with check (false);

alter table public.tenant_invites enable row level security;
revoke all on table public.tenant_invites from anon, authenticated;
drop policy if exists deny_direct_client_access on public.tenant_invites;
create policy deny_direct_client_access on public.tenant_invites
  for all to anon, authenticated
  using (false)
  with check (false);

alter table public.tenant_memberships enable row level security;
revoke all on table public.tenant_memberships from anon, authenticated;
drop policy if exists deny_direct_client_access on public.tenant_memberships;
create policy deny_direct_client_access on public.tenant_memberships
  for all to anon, authenticated
  using (false)
  with check (false);

alter table public.tenants enable row level security;
revoke all on table public.tenants from anon, authenticated;
drop policy if exists deny_direct_client_access on public.tenants;
create policy deny_direct_client_access on public.tenants
  for all to anon, authenticated
  using (false)
  with check (false);

alter table public.warehouses enable row level security;
revoke all on table public.warehouses from anon, authenticated;
drop policy if exists deny_direct_client_access on public.warehouses;
create policy deny_direct_client_access on public.warehouses
  for all to anon, authenticated
  using (false)
  with check (false);

comment on policy deny_direct_client_access on public.tenants is 'Explicit deny for direct anon/authenticated access; tenant data is accessed only through trusted, authorized server-side operations.';
