# Repository protection audit

- Final verification: 2026-11-13T13:53:57Z.
- GitHub branch API reports `protected=false` for both `main` and `staging`; branch SHAs remain `8d74dbda81eb483a26d779b782fd4b37e12af770` and `aed2733f62506ed87a5040a48f479753fdafe1b1` respectively.
- Initial and post-change `gh api --paginate repos/.../rulesets` returned an empty list; no ruleset is active.
- Classic branch protection GET for each branch returned HTTP 403: `Resource not accessible by integration` (GitHub REST resource unavailable to this integration).
- Both attempted POSTs to `repos/dlice8888/dlice-landing-page/rulesets` (main and staging) returned HTTP 403: `Resource not accessible by integration`. No ruleset was created.
- Existing contexts inspected: `static-checks` on staging and PR #71; Vercel on PR #63 and #71. PR #63 has no GitHub Actions test context. Staging’s `auth-negative` check failed on the latest staging SHA. The secret-free tenant static check is path-filtered to tenant-sensitive PRs, so making it globally required would block unrelated PRs; no safe path-specific ruleset mechanism was available.
- No protection workaround was attempted after the 403. Required approvals/checks, force-push/delete blocks, conversation resolution, and bypass restrictions are therefore not active/verified.

| Protection | main | staging |
|---|---|---|
| PR review required | FAIL — no active ruleset; classic API inaccessible | FAIL — no active ruleset; classic API inaccessible |
| Independent approval | FAIL — not enforced | FAIL — not enforced |
| Required status checks | FAIL — no active ruleset | FAIL — no active ruleset |
| Force push blocked | FAIL — no active ruleset; classic protection inaccessible | FAIL — no active ruleset; classic protection inaccessible |
| Branch deletion blocked | FAIL — no active ruleset; classic protection inaccessible | FAIL — no active ruleset; classic protection inaccessible |
| Conversation resolution | FAIL — no active ruleset | FAIL — no active ruleset |
| Bypass actors | NOT VERIFIED — no ruleset exists; classic API inaccessible | NOT VERIFIED — no ruleset exists; classic API inaccessible |

## Blocker

Repository ruleset write operations are blocked by HTTP 403 `Resource not accessible by integration`. An administrator with repository ruleset permissions must create and verify rulesets targeting `refs/heads/main` and `refs/heads/staging`. Staging must additionally establish an unconditional or otherwise safely enforceable tenant-isolation check before configuring it as required; the current security check is path-filtered.
