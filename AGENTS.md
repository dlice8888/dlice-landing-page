# Engineering workflow for D’Lice

Use the Superpowers development methodology for implementation work. Upstream: https://github.com/obra/superpowers
Pinned reference commit: 2ce8aa15d05bd57213e6f746f953aafb7ded7a8b

## Required workflow
1. For non-trivial changes, clarify the goal and constraints before implementation; write a concise design/spec and obtain owner approval when behavior or scope is ambiguous.
2. Write a short implementation plan with small, verifiable tasks and explicit file paths.
3. Use test-driven development where practical: add a failing regression test, run it to observe failure, implement the minimal fix, then rerun the test.
4. For bugs, reproduce first and investigate the root cause before changing code. Avoid speculative fixes.
5. Review the diff for correctness, security, scope, and regressions before completion.
6. Run the relevant tests/build/lint and report the actual commands and results. Never claim a check passed unless it was run.
7. Keep changes isolated on a feature branch and use a pull request. Do not merge or deploy to production without Owner approval.

## D’Lice-specific safety constraints
- Preserve existing brand colors and priority text unless the Owner explicitly authorizes changes.
- Do not change production Supabase/Vercel settings, secrets, plans, or paid resources without explicit approval.
- Treat authorization, branch isolation, RLS, CORS allowlists, and checkout/payment state as security-critical.
- Do not apply blanket RLS policies or blindly add/remove indexes.
- Do not treat an order being created as proof that payment succeeded.
- Keep secrets out of commits and logs.
- Test responsive ordering flows and relevant negative authorization cases before claiming acceptance.

## Upstream installation
This file records the workflow expectations; it does not vendor the upstream Superpowers source or install its agent-specific plugin. Install the official plugin for the coding-agent harness used by each developer, following the upstream README. For Codex, use the Plugins UI and search for “Superpowers”, or follow the upstream Codex installation instructions.
