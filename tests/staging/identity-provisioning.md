# Disposable Auth identities — staging only

This procedure is intentionally manual because the connected Supabase tools do not expose Auth Admin user creation or token minting. Do not insert directly into `auth.users`, do not reuse real staff accounts, and never place passwords or JWTs in Git.

## 1. Create six users in the STAGING Supabase project only

In Supabase Dashboard for project `higoadrzxnhzbbwhdbmh` → Authentication → Users, create unique disposable users and mark email as confirmed (no email delivery is needed for reserved test domains). Generate unique passwords and keep them in a local password manager. Suggested identifiers:

| Fixture | Suggested email | Profile / branch scope |
|---|---|---|
| Owner | `qa-owner-20261021@accounts.dlice.internal` | `owner`, global |
| Branch A manager | `qa-manager-a-20261021@accounts.dlice.internal` | `sales_admin`, QA-DLICE-A |
| Branch B manager | `qa-manager-b-20261021@accounts.dlice.internal` | `sales_admin`, QA-DLICE-B |
| Cashier A | `qa-cashier-a-20261021@accounts.dlice.internal` | `sales_admin`, POS only, QA-DLICE-A |
| Insufficient-permission staff | `qa-no-permission-20261021@accounts.dlice.internal` | `sales_admin`, empty permissions, QA-DLICE-A |
| Inactive staff | `qa-inactive-20261021@accounts.dlice.internal` | `sales_admin`, inactive, QA-DLICE-A |

Record each Auth user UUID. Never commit passwords, refresh tokens, access tokens, or the full user export.

## 2. Create profile and branch assignments

After replacing each `<..._USER_UUID>` placeholder with the UUID from the staging Auth Users page, run this SQL in the staging SQL editor only. It is idempotent for the profile rows and removes/recreates assignments only for these disposable users and QA fixture branches.

```sql
begin;

insert into public.admin_profiles
  (user_id, role, display_name, is_active, permissions, username)
values
  ('<OWNER_USER_UUID>'::uuid, 'owner', 'QA Owner (Disposable)', true,
   '[]'::jsonb, 'qa-owner-20261021'),
  ('<MANAGER_A_USER_UUID>'::uuid, 'sales_admin', 'QA Branch A Manager', true,
   '["orders","inventory","procurement","pos","finance","reports","branches"]'::jsonb, 'qa-manager-a-20261021'),
  ('<MANAGER_B_USER_UUID>'::uuid, 'sales_admin', 'QA Branch B Manager', true,
   '["orders","inventory","procurement","pos","finance","reports","branches"]'::jsonb, 'qa-manager-b-20261021'),
  ('<CASHIER_A_USER_UUID>'::uuid, 'sales_admin', 'QA Cashier A', true,
   '["pos"]'::jsonb, 'qa-cashier-a-20261021'),
  ('<NO_PERMISSION_USER_UUID>'::uuid, 'sales_admin', 'QA No Permission', true,
   '[]'::jsonb, 'qa-no-permission-20261021'),
  ('<INACTIVE_USER_UUID>'::uuid, 'sales_admin', 'QA Inactive Staff', false,
   '["orders"]'::jsonb, 'qa-inactive-20261021')
on conflict (user_id) do update set
  role = excluded.role,
  display_name = excluded.display_name,
  is_active = excluded.is_active,
  permissions = excluded.permissions,
  username = excluded.username,
  updated_at = now();

delete from public.branch_assignments
where user_id in (
  '<MANAGER_A_USER_UUID>'::uuid, '<MANAGER_B_USER_UUID>'::uuid,
  '<CASHIER_A_USER_UUID>'::uuid, '<NO_PERMISSION_USER_UUID>'::uuid,
  '<INACTIVE_USER_UUID>'::uuid
)
and branch_id in (
  '90000000-0000-4000-8000-000000000001'::uuid,
  '90000000-0000-4000-8000-000000000002'::uuid,
  '90000000-0000-4000-8000-000000000003'::uuid
);

insert into public.branch_assignments
  (branch_id, user_id, job_position_id, employment_status, starts_on, assigned_by)
values
  ('90000000-0000-4000-8000-000000000001'::uuid, '<MANAGER_A_USER_UUID>'::uuid, '81c829ec-8f42-437e-9b55-7cb5c3ce3ca4'::uuid, 'active', current_date, '<OWNER_USER_UUID>'::uuid),
  ('90000000-0000-4000-8000-000000000002'::uuid, '<MANAGER_B_USER_UUID>'::uuid, '81c829ec-8f42-437e-9b55-7cb5c3ce3ca4'::uuid, 'active', current_date, '<OWNER_USER_UUID>'::uuid),
  ('90000000-0000-4000-8000-000000000001'::uuid, '<CASHIER_A_USER_UUID>'::uuid, '8b537e68-5b3e-4072-9ce0-c482286ea531'::uuid, 'active', current_date, '<OWNER_USER_UUID>'::uuid),
  ('90000000-0000-4000-8000-000000000001'::uuid, '<NO_PERMISSION_USER_UUID>'::uuid, '038c6cb8-ca3e-4bd8-82a0-bbd9f09379db'::uuid, 'active', current_date, '<OWNER_USER_UUID>'::uuid),
  ('90000000-0000-4000-8000-000000000001'::uuid, '<INACTIVE_USER_UUID>'::uuid, '038c6cb8-ca3e-4bd8-82a0-bbd9f09379db'::uuid, 'active', current_date, '<OWNER_USER_UUID>'::uuid);

commit;
```

**Do not execute this template until all six placeholders are replaced with real UUIDs from the staging Auth Users page.** Never run it against production. The Owner profile is intentionally global; keep its credentials only in the password manager and revoke/delete the disposable user after acceptance testing.

## 3. Obtain short-lived access tokens outside Git

Use the staging Auth login flow with the disposable email/password pairs to obtain access tokens. Export them only in the local runner shell as `TEST_STAFF_JWT` and `TEST_OWNER_JWT`; do not paste tokens into chat, issues, logs, or repository files. Use the Branch A manager token with `TEST_BRANCH_B_ID=90000000-0000-4000-8000-000000000002` to test cross-branch denial. The HTTP runner's results are not evidence until actually executed from a networked environment.

## 4. Expected IDs

- QA-DLICE-A / WIB: `90000000-0000-4000-8000-000000000001`
- QA-DLICE-B / WITA: `90000000-0000-4000-8000-000000000002`
- QA-DLICE-C / WIT: `90000000-0000-4000-8000-000000000003`
- Inactive test product: `90000000-0000-4000-8000-000000000100`
- Branch B capacity fixture: `90000000-0000-4000-8000-000000000601`

These fixture branches are active for internal ERP tests only. Online checkout remains disabled on all three.


## 5. Browser and CI smoke runner

The staging branch now includes a manual GitHub Actions workflow at `.github/workflows/staging-p0-smoke.yml`. Before dispatching it:

1. In GitHub → Settings → Environments, configure the `staging` environment (or remove the environment gate only if repository policy allows).
2. Add these environment secrets to the `staging` environment. Never store access tokens in source files:
   - `STAGING_SUPABASE_URL` — `https://higoadrzxnhzbbwhdbmh.supabase.co`
   - `STAGING_SUPABASE_PUBLIC_KEY` — staging publishable/anon key only
   - `STAGING_EDGE_FUNCTION_URL` — `https://higoadrzxnhzbbwhdbmh.supabase.co/functions/v1/dlice-orders`
   - `STAGING_TEST_OWNER_JWT`
   - `STAGING_TEST_BRANCH_A_MANAGER_JWT`
   - `STAGING_TEST_NO_PERMISSION_JWT`
   - `STAGING_TEST_INACTIVE_STAFF_JWT`
3. Add the current stable branch Preview alias to the staging Edge Function secret `DLICE_ALLOWED_ORIGINS`, preserving existing entries:
   `https://dlice-landing-page-git-feat-fnb-os-stagin-f4a8a6-dlice8888-7332.vercel.app`
   The current deployment-specific Preview URL is `https://dlice-landing-page-1u0n1aix1-dlice8888-7332.vercel.app`; use the stable branch alias as the browser target so subsequent deployments keep the same origin. Recheck the alias before running.
4. In GitHub → Actions → **Staging P0 and browser smoke** → Run workflow, enter:
   `https://dlice-landing-page-git-feat-fnb-os-stagin-f4a8a6-dlice8888-7332.vercel.app`
5. Download the two workflow artifacts. The P0 job must have no FAIL or BLOCKED checks. A job that exits with code 2 means prerequisites are missing; do not report it as a pass.

The browser job only checks Preview reachability, login shell, and desktop/mobile layout. It does not perform authenticated business transactions or replace the four cross-module acceptance tests.
