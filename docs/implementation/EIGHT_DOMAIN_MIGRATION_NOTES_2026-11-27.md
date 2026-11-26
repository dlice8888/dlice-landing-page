# Eight-domain migration candidate — release notes

**Candidate branch:** `feat/eight-domain-official-migrations-20261127`  
**Base:** PR #145 exact head `6901d5f26d60161921c5606fd4516f806a9519da`  
**Status:** draft only; not applied to dlice-staging or Production.

## Migration sequence

The two POS migrations below restore source parity with entries already present in the staging migration history:

- `20261124134101_pos_checkout_lifecycle.sql`
- `20261124134222_pos_checkout_fk_supporting_indexes.sql`

Eight official migrations were generated with Supabase CLI `migration new` from the reviewed SQL drafts, in dependency order:

1. `20261126192455_crm_loyalty_financial_close.sql` — CRM identity, consent, loyalty, Finance-close adapter and expiry.
2. `20261126192458_hr_workforce_payroll_finance.sql` — workforce, employee lifecycle, payroll, Finance posting and payment adapters.
3. `20261126192501_delivery_fulfillment_provider.sql` — dispatch, provider storage, proof-of-delivery, atomic worker and reconciliation.
4. `20261126192504_franchise_expansion.sql` — application, due diligence, agreement, site opening and royalty.
5. `20261126192506_procurement_supplier.sql` — tenant supplier links, receiving, invoice and AP lifecycle.
6. `20261126192509_bi_analytics.sql` — metric definitions, lineage, freshness, reconciliation and publication.
7. `20261126192512_saas_tenant_billing.sql` — plan versions, entitlements, usage, invoicing and tenant offboarding.
8. `20261126192514_executive_command_center.sql` — targets, alerts, branch ranking and drill-down evidence.

The source set declares 71 distinct new tables across the eight domains. The migrations preserve the source RLS enablement loops, revoke direct anon/authenticated table access, and grant table privileges to `service_role` only. `supabase/tests/eight_domain_rls_acl.test.sql` adds 994 pgTAP assertions for table existence, RLS, client-role denial and service-role privileges. CRM's 44-assertion suite is promoted to `supabase/tests/crm_loyalty.test.sql`.

## Validation gates

- Local dependency-free Node contracts: 226/226 passed before this SQL runtime correction.
- Staging release contract checks: passed; static only.
- Exact candidate disposable replay initially failed in Delivery because the draft used the invalid cross-schema name `public.storage.objects`. The migration and source draft now use the Supabase Storage schema `storage.objects`. A fresh exact-head disposable replay and all pgTAP suites must pass before this PR is accepted.
- No staging migration, Edge Function deployment, Auth metadata, secret, or Vercel configuration was changed.

## Rollout constraints

Keep `TENANT_ISOLATION_RELEASED=false` and `PUBLIC_TENANT_ROUTING_RELEASED=false`. Do not apply this migration set until the disposable replay, pgTAP, independent review, source/history parity review and exact-head P01–P09 checks pass. Any eventual staging application requires explicit staging approval and one-migration-at-a-time evidence. Never apply these migrations to Production.

These are additive schema/workflow changes. No automatic DROP-based rollback is supplied; if a later staging application fails, stop the rollout, preserve evidence and use a reviewed forward-fix or a verified staging restore plan.

The malformed Delivery SHA-256 predicate was in the atomic-adapter extension draft (not the base fulfillment draft); that source has now been corrected as well. The new static contract scans every source draft and official migration for unmatched regex string quotes.


The Delivery provider webhook predicate also lacked its terminating PL/pgSQL `THEN`; this is now present in both the official migration and source draft. The contract suite explicitly checks the Delivery hash and Franchise email validation predicates.
