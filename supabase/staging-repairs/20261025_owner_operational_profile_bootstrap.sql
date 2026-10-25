-- STAGING-ONLY ONE-TIME REPAIR — do not run against production.
-- Root cause: the sole pre-provisioned staging Auth identity authenticated successfully,
-- but public.admin_profiles had zero rows, so getAdmin() rejected every operational action.
-- The repair has already been applied to project higoadrzxnhzbbwhdbmh.
-- This file is retained as an auditable recovery procedure, NOT an automatic migration.

insert into public.admin_profiles (user_id, role, display_name, is_active, permissions, username)
select u.id, 'owner', 'D''Lice Owner', true, '["*"]'::jsonb, 'dlice8888'
from auth.users u
where lower(u.email) = 'dlice8888@accounts.dlice.internal'
on conflict (user_id) do update
set role = 'owner',
    display_name = coalesce(public.admin_profiles.display_name, excluded.display_name),
    is_active = true,
    permissions = '["*"]'::jsonb,
    username = excluded.username,
    updated_at = now();

-- Verify: exactly one active Owner profile should exist for the staging identity.
select p.user_id, p.role, p.is_active, p.username, p.permissions
from public.admin_profiles p
join auth.users u on u.id = p.user_id
where lower(u.email) = 'dlice8888@accounts.dlice.internal';
