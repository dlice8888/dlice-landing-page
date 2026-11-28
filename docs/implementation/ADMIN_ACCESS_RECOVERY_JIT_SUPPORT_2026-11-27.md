# Admin, Identity & SaaS Support Access (2026-11-27)

## Feature IDs started
- D15-F06 — Sessions/devices and access reviews.
- D15-F07 — Recovery and offboarding.
- D16-F06 — Support access with approval/audit.

## Implemented
`src/admin-access-review-recovery-support-workflows.mjs` adds:
- independent periodic access review over every active device and session, with explicit retain/revoke decisions and server-side revocation;
- account recovery gated by official Auth recovery proof, independent approval, factor rotation and revocation of all previous sessions;
- tenant-owner-approved just-in-time support sessions limited to explicit read-only scopes and a maximum 30-minute lifetime;
- immediate JIT support session revocation with zero-active-session verification.

Contract tests cover self-review denial, missing decisions, unverified recovery proof, remaining sessions, support write-scope rejection, excessive duration and successful grant/revoke.

## Remaining acceptance
- Connect to Supabase Auth Admin official APIs and actual session/device inventory; no Auth metadata SQL.
- Persist access review records, recovery events and JIT support grants with RLS, append-only audit and short retention.
- Build admin/tenant-owner UI for access reviews, device inventory, recovery and support approval.
- Implement actual token/session revocation and verify refresh-token/session invalidation.
- Enforce read-only support scope at RPC/table layer, tenant-specific impersonation controls, visible support banner and session recording/audit.
- Add periodic access review scheduler, recovery notification and security alerts.
- Staging tenant A/B and role-boundary E2E; no Production account changes in this batch.
