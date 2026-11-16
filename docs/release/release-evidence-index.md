# Release evidence index

**Snapshot date:** 2026-11-16  
**Decision:** NO-GO; administrative/runtime evidence remains blocked or not run.

| Evidence | Reference | Environment / commit | Result |
|---|---|---|---|
| Baseline repository state | [staging-baseline.md](./staging-baseline.md) | Initial checkout `33a561147d20aa0e99d4e7963d62c73dfeb56fe2`; main `8d74dbda81eb483a26d779b782fd4b37e12af770`; staging `aed2733f62506ed87a5040a48f479753fdafe1b1` | Recorded |
| PR #75 checks | https://github.com/dlice8888/dlice-landing-page/pull/75/checks | PR head `ac1a64b9cf4a57f2ac60d4ea82a8f7001e27a2f4` | PASS; no approval |
| Tenant approval security fix | https://github.com/dlice8888/dlice-landing-page/commit/ac1a64b9cf4a57f2ac60d4ea82a8f7001e27a2f4 | PR #75 head `ac1a64b9cf4a57f2ac60d4ea82a8f7001e27a2f4` | Pushed; focused local tests PASS; GitHub checks PASS |
| PR #75 Preview | https://vercel.com/dlice8888-7332/dlice-landing-page/cgqcJZzEYrX91XaDLYshYaWJeQ2Q | PR #75 security-fix head | Ready; not production |
| PR #76 disposable replay | https://github.com/dlice8888/dlice-landing-page/actions/runs/43622512657 | Disposable local DB; PR #76 head | PASS |
| PR #77 disposable replay | https://github.com/dlice8888/dlice-landing-page/actions/runs/43570024409 | Disposable local DB; PR #77 head | PASS |
| PR #78 disposable replay | https://github.com/dlice8888/dlice-landing-page/actions/runs/43573222955 | Disposable local DB; PR #78 head | PASS |
| Scheduled procurement E2E | https://github.com/dlice8888/dlice-landing-page/actions/runs/43844108130 | `main`, `8d74dbda81eb483a26d779b782fd4b37e12af770` | FAIL |
| Scheduled KDS/POS/stock E2E | https://github.com/dlice8888/dlice-landing-page/actions/runs/43843008479 | `main`, `8d74dbda81eb483a26d779b782fd4b37e12af770` | FAIL |
| Tenant authorization tests | Local `node --test` and Deno test output | PR #75 worktree | PASS (8/8 Node; 7/7 Deno) |
| Staging secret/variable inventory | GitHub Environment APIs | `staging` | BLOCKED (HTTP 403; absence not inferred) |
| Staging P01–P09 | No trusted workflow run | Supabase staging | BLOCKED / NOT RUN |
| Staging migration, backup/restore, performance | No authorized execution | Supabase staging | NOT RUN |

For subsequent evidence, add workflow run and job URLs, exact source commit,
migration identifier, deployment identifier, timestamp, environment,
actor/independent approver, and result. Never include secret values, passwords,
JWTs, or service-role credentials.
