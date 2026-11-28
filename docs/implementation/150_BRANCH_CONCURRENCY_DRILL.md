# 150-branch disposable concurrency drill

## Purpose
Start a reproducible, free PostgreSQL 17 load probe for the 150-branch scale requirement without using Supabase paid branches, staging business data, or Production.

## Scenario
- Create two tenant fixtures: Tenant A has 150 branches; Tenant B has one.
- Enable RLS on the branch table and grant only authenticated SELECT.
- Run 50 concurrent clients (4 worker threads) for Tenant A and Tenant B separately.
- Each transaction switches to the authenticated role, sets the tenant context, verifies its own branch count, and asserts that cross-tenant rows remain invisible.
- Capture transaction throughput and p95/p99 query latency from pgbench logs.

## Acceptance boundary
The test must finish with zero failed transactions, exact branch fixture counts, and no cross-tenant rows visible. It measures a database read/isolation workload only.

## Limitations
This is not a complete D’Lice application/API benchmark. It does not cover POS writes, stock locks, kitchen, Finance, storage, Edge Functions, multi-region network latency, 150 real branches or production-like data volume. p95/p99 values are observations, not an approved SLO until workload assumptions and target thresholds are signed off.
