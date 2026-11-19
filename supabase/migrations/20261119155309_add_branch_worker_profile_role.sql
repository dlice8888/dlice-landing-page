-- Add an explicit non-admin profile class for ordinary tenant workers.
-- Tenant permissions remain sourced exclusively from active tenant_memberships.
-- This migration is source-only until reviewed and applied through the staging migration gate.
alter table public.admin_profiles
  drop constraint if exists admin_profiles_role_check;

alter table public.admin_profiles
  add constraint admin_profiles_role_check
  check (role = any (array['sales_admin'::text, 'branch_worker'::text, 'owner'::text]));

comment on column public.admin_profiles.role is
  'Identity classification only: owner, sales_admin, or branch_worker. Tenant authorization is derived from active tenant_memberships and branch_assignments.';
