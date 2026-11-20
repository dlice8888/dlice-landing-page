# Superpowers engineering method for D’Lice

The D’Lice repository adopts the Superpowers-style engineering workflow as a project-level operating standard, recorded in the root `AGENTS.md`.

## Scope

- Clarify the goal and acceptance criteria before non-trivial work.
- Plan small, reviewable tasks with explicit files and dependencies.
- Use test-driven development and reproduce bugs before fixing them.
- Review full diffs for security, correctness, scope and regressions.
- Run exact-head tests and report evidence without overstating results.
- Integrate PRs and migrations incrementally, never as a bulk merge.
- Keep production and shared staging behind explicit release gates.

## Dependency policy

This project does not vendor or automatically initialize an external Git submodule for the method. The workflow is recorded locally so the project standard remains available without introducing an unreviewed upstream dependency or assuming that a submodule activates agent skills. Individual developers may use compatible tooling separately, while the D’Lice-specific safety constraints in `AGENTS.md` remain authoritative.

## Provenance

The method and D’Lice-specific constraints were adapted from the workflow documentation proposed in closed PR #62. The optional upstream submodule and its verification workflow were not copied. No application runtime, Supabase setting, Vercel setting or production configuration is changed by these documents.
