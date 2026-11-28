BLOCKED ACCEPTANCE REMEDIATION (2026-11-27)

Four blocked features moved into active implementation:
- D04-F10 — Theoretical vs actual usage/waste variance.
- D05-F11 — POS/production approved recipe version parity.
- D08-F03 — Opening readiness changes branch operating status.
- D11-F03 — Payment provider fee and settlement variance.

Implemented in src/blocked-acceptance-remediation-workflows.mjs:
- Theoretical recipe usage versus posted/reconciled stock consumption variance by ingredient and cost.
- Exact approved recipe version and immutable snapshot hash parity between POS sale line and production batch.
- Branch opening readiness evaluator and atomic operating-status transition only after every mandatory evidence check is approved and verified.
- Provider settlement fee/net/bank reconciliation from an approved fee schedule, with tolerance and variance reporting.

Contract tests cover cross-domain parity, waste variance, branch readiness, provider fee calculation and settlement variance.

Remaining acceptance:
- Production-usage variance requires real production runs and stock ledger references, manager review, corrective action and Finance reconciliation.
- Recipe parity requires canonical recipe snapshots and live POS/KDS/production adapters; the same immutable hash must be persisted across modules.
- Branch opening requires canonical checklist/evidence schema, role-based approval and staging lifecycle E2E.
- Provider fee reconciliation requires approved provider fee schedules, actual provider sandbox settlement and matched bank statement; no provider is marked active without evidence.

Still blocked:
- D01-F09 Owner company→region→branch→shift→transaction drill-down remains blocked until the official Auth Admin metadata path and Owner allowlist are independently verified. The read-only staging check found zero platform_owner=true Auth users. No SQL Auth metadata update or bypass is allowed.
