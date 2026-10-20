# D’Lice staging audit — 2026-10-21

## Scope and safety
- Repository: `dlice8888/dlice-landing-page`.
- UX/CX branch: `feat/staging-ux-cx-final-reconcile-20261021`, based on `feat/staging-erp-workflows-api`.
- Staging Supabase: `higoadrzxnhzbbwhdbmh` (`dlice-staging`), region `ap-southeast-1`.
- Production Supabase: `gdjlkrmlsurcdbwnmqgg`; production site `https://dlice.vercel.app/`.
- No production database, environment variable, domain, or deployment was changed by this UX branch.
- No paid dependencies or new runtime packages were added.

## Confirmed current state
- Staging database is ACTIVE_HEALTHY on PostgreSQL 17.
- Staging Edge Function `dlice-orders` is ACTIVE at version 31 and has `verify_jwt=false`; inspect handler-level authorization, tracking-token validation, and per-action checks carefully because the platform JWT gate is disabled.
- Staging migration history includes order/payment controls, rate limiting, privacy-preserving funnel metrics, RLS hardening, multi-branch POS/ERP, branch-routed checkout capacity, finance/refund/settlement guards, atomic recipe activation and deterministic production stock locking through `20261020202841`.
- Current GitHub PR #22 is draft and adds checkout branch assignment/capacity, order fulfillment, purchase receiving, BOM/production, settlement, refunds, cash reconciliation, tax settings and fiscal-period controls. It lists full role-based browser E2E, negative cross-branch tests, concurrency tests and payment-proof lifecycle tests as outstanding.
- Vercel preview deployments are READY for commits on `feat/staging-erp-workflows-api`; the newest observed deployment was built from commit `f762c688a7fba92f1a1c7d81d0deef407aea6774` (see Vercel metadata for exact SHA if rechecking).
- Supabase Security Advisor issue reported by the staging release notes: leaked-password protection is disabled and requires enabling in Supabase Auth password security settings.
- Figma account context reports Starter plan and a View seat, with Code Layers disabled. Direct canvas edits may be blocked by permissions; no claim of a Figma file being edited is made from this code change.

## UX/CX findings and changes in this branch
- Existing design already includes wine/rose/cream tokens, DM Sans + Playfair Display, subtle entrance transitions, focus rings, 44px minimum primary touch targets, iOS safe-area handling, and reduced-motion support.
- Tablet breakpoint was too broad in practice: a 3-column product grid could make cards narrow at 761–1024px. Set a two-column grid in this range and normalized image aspect ratios.
- Narrow phone layouts can compress the brand/navigation and order-item rows. Added a <=360px treatment and min-width guards to prevent grid/flex overflow.
- Form controls are normalized to 16px to avoid iOS Safari input zoom; date/time controls and order actions get larger touch heights.
- Added consistent touch feedback, text wrapping guards, and a second explicit reduced-motion override for the hero entrance and reveal classes.
- Existing palette, brand text, product copy, order labels and customer-facing priority text are not rewritten by this branch.

## Required acceptance gates before production
1. Verify preview is built from this exact branch/commit and is isolated from production env vars.
2. Test Android Chrome at 320/360/390/430px; iPhone Safari at 375/390/430px including safe areas; iPad/tablet at 768/820/1024px; desktop at 1280/1440px.
3. Check horizontal overflow, image cropping, keyboard focus, 44–48px touch targets, form validation, date/time selection, multi-item quantities, summary totals, receipt confirmation, proof upload, and WhatsApp finalization.
4. Test `prefers-reduced-motion: reduce` and keyboard-only navigation; verify no content remains hidden when IntersectionObserver is unavailable.
5. Run browser E2E with real staging accounts for Owner and every staff role, plus negative cross-branch read/write tests.
6. Exercise checkout capacity races, concurrent stock/receiving/production writes, settlement matching, refund caps/final states, fiscal-period close guards, and payment-proof version changes.
7. Review RLS and every `dlice-orders` action with `verify_jwt=false`; confirm sensitive writes remain server-authorized and private payment proofs are not publicly readable.
8. Enable leaked-password protection in Supabase Auth settings and rerun Security Advisor.
9. Configure real branch address/city, online availability and per-product/date capacity before enabling branch-routed checkout. Planned branch slots are not operating locations.
10. Keep all ERP changes in staging; do not merge/promote to `main` or production until all gates pass and the Owner explicitly approves.
