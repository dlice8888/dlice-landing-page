# Staging Tenant B owner bootstrap (controlled administrative path)

## Scope and release posture

This is a one-time staging bootstrap for tenant `dlice-qa-isolation-b` only.

- Tenant ID: `00000000-0000-4000-8000-000000000002`
- QA branch ID: `90000000-0000-4000-8000-000000000004`
- Project ref: `higoadrzxnhzbbwhdbmh`
- General tenant isolation remains **HOLD**. Keep `TENANT_ISOLATION_RELEASED=false`.
- The action is unavailable unless the staging-only feature flag `DLICE_TENANT_B_BOOTSTRAP_ENABLED=true` is explicitly set.
- The action requires both the server-side platform-owner UUID allowlist and `app_metadata.platform_owner=true`. It does not trust user metadata.
- It rejects targets that already have any tenant membership, rejects unverified/inactive accounts, and grants only `branches`, `inventory`, and `procurement` profile permissions.
- It does not accept or return passwords, JWTs, API keys, or other secrets.

## Authorized operator procedure

1. A platform owner signs in to the existing admin panel and creates a dedicated staff account using the existing **Create Staff** operation. Use a unique username and a temporary password generated/stored in an approved password manager. Do not send the password through ChatGPT, GitHub comments, logs, or issue descriptions. The existing staff creation action confirms the internal Auth identity and creates an active `sales_admin` profile.
2. In the staging Supabase project only, an authorized project administrator temporarily sets the Edge Function secret/variable `DLICE_TENANT_B_BOOTSTRAP_ENABLED=true`. Do not set this on production.
3. The platform owner retrieves the new account's `user_id` from the admin staff list. The platform owner then calls the existing `dlice-orders` Edge Function with their own authenticated session:
   
   ```http
   POST https://higoadrzxnhzbbwhdbmh.supabase.co/functions/v1/dlice-orders
   Authorization: Bearer <PLATFORM_OWNER_ACCESS_TOKEN>
   apikey: <STAGING_PUBLISHABLE_KEY>
   Content-Type: application/json

   {
     "action": "platform-bootstrap-tenant-b-owner",
     "user_id": "<NEW_STAFF_USER_UUID>"
   }
   ```

   Obtain the access token from the signed-in platform-owner session locally; never paste it into chat or a GitHub issue. The response must include `ok: true`, `role: tenant_owner`, `status: active`, and `audit_recorded: true`.
4. Immediately set `DLICE_TENANT_B_BOOTSTRAP_ENABLED=false` (or remove the flag) in staging after the one-time action. Keep the platform-owner allowlist and app metadata controls intact.
5. The new account holder signs in through the normal admin login using the dedicated username and receives the temporary password through a secure out-of-band channel, then changes it. Verify their own active Tenant B membership with `erp-list-tenant-memberships`. The account must have no membership in any other tenant.

## Operational sequence after activation

1. Tenant Owner creates the QA branch warehouse through `erp-create-warehouse`. The endpoint writes `erp_warehouse_created` to `admin_audit_logs`; if audit insertion fails, the warehouse write is rolled back.
2. The existing Tenant B branch manager (or another authorized requester) creates the purchase requisition with `erp-create-purchase-requisition`.
3. A different Tenant B tenant_owner/admin approves it with `erp-transition-purchase-requisition`. Self-approval remains denied.
4. Tenant Owner converts the approved requisition to a draft PO, then submits, approves, and orders the PO through `erp-update-purchase-order`. PO self-approval remains denied.
5. Tenant Owner or authorized inventory/procurement staff posts goods receipt through `erp-receive-purchase-order`.
6. Tenant Owner/admin verifies receipt lines, stock movements, PO status, and matching `admin_audit_logs` through `erp-reconcile-purchase-receipt`.

## Verification evidence required before closing the blocker

- Tenant B has exactly the intended dedicated active `tenant_owner` membership.
- The dedicated identity has no membership in Tenant A or any other tenant.
- One warehouse exists on the QA branch and has an `erp_warehouse_created` audit event.
- Requisition has requester and a different approver, with approved/converted timestamps and audit entries.
- PO has a different approver, status `ordered`, and matching PO audit events.
- Goods receipt is posted; receipt items, stock movements, branch inventory balance, PO received/partially_received status, and receipt audit event reconcile exactly.
- No workflow probe is dispatched until PR #71 receives independent review and the staging credential preflight is valid. No tenant-isolation release flag is changed by this bootstrap.
