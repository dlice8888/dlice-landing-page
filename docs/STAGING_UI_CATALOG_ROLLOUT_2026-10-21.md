# Staging UI and catalog rollout — 2026-10-21

## Scope
This rollout is limited to `feat/staging-elegant-responsive-motion` and the staging Supabase project `higoadrzxnhzbbwhdbmh`. Production branch `main`, production Supabase project `gdjlkrmlsurcdbwnmqgg`, and `https://dlice.vercel.app/` are out of scope.

## UI changes
- Keep the established color palette, logo, priority copy, and section order.
- Add subtle reveal and hover transitions, keyboard focus rings, larger touch targets, safer mobile input sizing, and responsive tablet/mobile spacing.
- Respect `prefers-reduced-motion`; no animation should block content.
- Use the same product photo files already present on the production branch as image fallbacks when the staging catalog has no Storage `image_path`.

## Catalog migration
Apply `supabase/migrations/20261020185740_align_product_copy_and_prices.sql` to staging only after PR review/merge. It updates the current product catalog names, descriptive copy, display order, categories, and official prices:
- Es Buah Premium D’Lice — Rp60.000
- Cadbury Braid Cheese — Rp70.000
- Cadbury Kunafa Pistachio — Rp90.000

Existing orders keep their immutable item-name and price snapshots. The migration does not write to orders, payments, proofs, reservations, admin settings, or production.

## Staging validation
1. Verify migration history records version `20261020185740`.
2. Query the three active products and confirm exact names, descriptions, and prices.
3. Open the current Vercel Preview URL for the staging branch and verify the three matching photos load.
4. Check Android/mobile, iOS/mobile, tablet, and desktop layout, including order summary, form controls, focus behavior, and reduced-motion preference.
5. Confirm the production domain and production Supabase project remain unchanged.
6. Keep promotion blocked until full checkout/payment/tracking E2E and explicit Owner approval are recorded.
