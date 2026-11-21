# D’Lice feature progress scoring standard — 21 November 2026

## Why percentages are not copied from the old estimates

A feature marked PARTIAL only means that some implementation evidence exists. It does not mean that the feature is 50%, 70%, or any other fixed percentage complete. Historical domain estimates in the original PRD register are not current acceptance scores.

## Weighted evidence model

| Acceptance dimension | Weight |
|---|---:|
| Code and UI implementation | 20% |
| Database integrity and migrations | 20% |
| Authorization and tenant/branch scope | 15% |
| Automated contract and unit tests | 15% |
| End-to-end browser or API workflow | 20% |
| Operational reconciliation and observability | 10% |
| **Total** | **100%** |

For each feature, each dimension is split into explicit pass/fail acceptance criteria. A dimension earns its weight only when a current evidence artifact (commit/PR, migration/test, CI run, runtime trace, screenshot, or reconciled database query) demonstrates that criterion. A BLOCKED or SKIPPED test earns zero for that criterion.

## Status transitions

- NOT VERIFIED → PARTIAL: a concrete implementation task/PR has started and evidence is linked; this is not acceptance.
- PARTIAL → DONE: 100% weighted score, every required workflow passes, code and database checks pass, no BLOCKED/SKIPPED, and independent review/release gates pass where required.
- BLOCKED remains visible while an external prerequisite prevents execution. Track its work status separately (e.g. IN_PROGRESS or EXTERNAL_ACTION_REQUIRED).

## Current snapshot

- 189 PRD features across 18 domains.
- 84 PARTIAL, 96 NOT VERIFIED, 9 BLOCKED.
- Two features have current weighted scores in SaaS Tenant Management: Tenant/member isolation = 28% and Tenant directory/tenant onboarding = 30% (both PR #126). The other 82 PARTIAL features still require per-feature decomposition and evidence before a score is assigned; historical domain estimates are not substituted.
- Feature 8 (permission-change audit) is IN_PROGRESS in Draft PR #120. Feature 9 (leaked-password protection) has free application-layer mitigation in Draft PR #124 but native Supabase protection and direct Auth bypass remain unresolved. Tenant/member isolation moved to PARTIAL at 28%, and tenant directory/onboarding moved to PARTIAL at 20% after PR #126 implementation and test work.

## Non-negotiable reporting rule

Never count a code artifact, schema/table, green build, preview deployment, negative-only authorization test, or an unexecuted/blocked/skipped workflow as feature completion. Every DONE claim must point to the passing evidence for all required dimensions.
