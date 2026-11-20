-- Staging-only, one-time GitHub OIDC session issuance audit.
-- This does not create Auth identities or grant tenant permissions.
create table if not exists public.staging_machine_session_issuances (
  id uuid primary key default gen_random_uuid(),
  github_run_id text not null,
  github_run_attempt integer not null check (github_run_attempt > 0),
  github_jti text not null,
  tenant_slot text not null check (tenant_slot in ('A','B')),
  auth_user_id uuid not null references auth.users(id) on delete cascade,
  issued_at timestamptz not null default now(),
  unique (github_run_id, github_run_attempt, tenant_slot),
  unique (github_jti, tenant_slot)
);
alter table public.staging_machine_session_issuances enable row level security;
revoke all on table public.staging_machine_session_issuances from public, anon, authenticated;
grant all on table public.staging_machine_session_issuances to service_role;
