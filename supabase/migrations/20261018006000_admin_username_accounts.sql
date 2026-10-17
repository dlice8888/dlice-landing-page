-- Username-based admin identities for D'Lice. Existing profiles remain valid until usernames are assigned.
alter table public.admin_profiles
  add column if not exists username text;

create unique index if not exists admin_profiles_username_lower_uidx
  on public.admin_profiles (lower(username))
  where username is not null;

comment on column public.admin_profiles.username is
  'Login username; case-insensitive and unique. Authentication email is internal only.';
