# Branch deletion allowlist

- Evaluated against `origin/staging` `aed2733f62506ed87a5040a48f479753fdafe1b1` at 2026-11-13T13:43Z UTC.
- Only rows below passed all deletion acceptance criteria. Each deletion must be individually verified.

| Branch | Exact SHA | PR | Merge status | Latest staging ancestry | Migration result | No open PR dependency | No audit evidence lost | Justification |
|---|---|---|---|---|---|---|---|---|
| `ci/staging-cors-runtime-gate-20261023` | `ee73bd9625fbd2d5b9c2ddf725a71b7db5226e32` | #37 | MERGED 2026-10-23T16:04:20Z to `staging` (merge `6a38ff194ca13098aa2c72a2ad15e84bec6596e0`) | YES; 0 ahead / 45 behind | No migration changes in PR/branch diff; not applicable | YES | YES; work retained in staging/merged PR | Exact branch tip is contained in staging; merged PR files contain no migrations; no open head/base refs or workflow branch references; no audit flag. |
| `fix/staging-cors-secret-only-20261023` | `576d0781281ea826d19824990cd1668190d1ab46` | #32 | MERGED 2026-10-23T15:29:07Z to `staging` (merge `e7fd6fe5f379354648ff3db290eb96583937c788`) | YES; 0 ahead / 71 behind | No migration changes in PR/branch diff; not applicable | YES | YES; work retained in staging/merged PR | Exact branch tip is contained in staging; merged PR files contain no migrations; no open head/base refs or workflow branch references; no audit flag. |
| `test/staging-procurement-e2e-contract-v2` | `57ef016b7fd1a5ff436f16ece40b72ed2a1fc410` | #39 | MERGED 2026-10-23T16:10:10Z to `staging` (merge `17571890d29e2fe9f4410cb57f53de073427b9f5`) | YES; 0 ahead / 24 behind | No migration changes in PR/branch diff; not applicable | YES | YES; work retained in staging/merged PR | Exact branch tip is contained in staging; merged PR files contain no migrations; no open head/base refs or workflow branch references; no audit flag. |

All other branches are excluded and preserved because one or more criteria are false or unverified.
