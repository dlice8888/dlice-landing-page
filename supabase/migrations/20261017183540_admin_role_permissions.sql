-- Fine-grained permissions for D'Lice admin profiles.
alter table public.admin_profiles
  add column if not exists permissions jsonb not null default '["orders"]'::jsonb;

-- Owner always has full access in the Edge Function, independent of this column.
update public.admin_profiles
set permissions = '["orders"]'::jsonb
where role <> 'owner' and permissions is null;

alter table public.admin_profiles
  alter column permissions set default '["orders"]'::jsonb;

comment on column public.admin_profiles.permissions is
  'Allowed admin sections: orders, catalog, finance, reports, settings, staff. Owner bypasses this list.';
