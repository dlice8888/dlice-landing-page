# Superpowers integration record

- Upstream: https://github.com/obra/superpowers
- Pinned upstream commit checked during preparation: `2ce8aa15d05bd57213e6f746f953aafb7ded7a8b`
- Project workflow rules: [`/AGENTS.md`](../../AGENTS.md)

## Important status

This change adds repository-level engineering guardrails inspired by Superpowers. It does **not** contain a clone, Git submodule, or vendored copy of the upstream repository. The available GitHub operations in this session can commit files and open pull requests, but do not provide a way to run `git clone` or safely construct a submodule gitlink while preserving the current repository tree. Do not describe the upstream source as installed until a real clone/submodule has been added and verified.

## Recommended next step

From a development environment with Git access, install the official Superpowers plugin for the coding-agent harness in use (the upstream README recommends per-harness installation). Keep the source upstream rather than copying a partial set of skills into the website. If the team specifically wants the source pinned inside this repository, add it as a Git submodule in a local Git checkout, commit both `.gitmodules` and the submodule gitlink, then verify a fresh clone with submodules enabled.
