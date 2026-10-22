# Superpowers integration record

- Upstream: https://github.com/obra/superpowers
- Pinned upstream commit: `2ce8aa15d05bd57213e6f746f953aafb7ded7a8b` (Superpowers v7.0.1)
- Submodule path: `tools/superpowers`
- Submodule configuration: [`.gitmodules`](../../.gitmodules)
- Project workflow rules: [`/AGENTS.md`](../../AGENTS.md)

## What is committed

The integration branch now contains a real Git submodule gitlink at `tools/superpowers`, pinned to the upstream commit above, plus the `.gitmodules` configuration. This references the complete upstream repository without copying its files into the D’Lice website's own Git tree.

To initialize the source after cloning this repository, run:

```bash
git clone --recurse-submodules https://github.com/dlice8888/dlice-landing-page.git
```

If you already cloned the repository without submodules:

```bash
git submodule update --init --recursive
```

To verify the pinned source:

```bash
git -C tools/superpowers rev-parse HEAD
```

Expected commit: `2ce8aa15d05bd57213e6f746f953aafb7ded7a8b`.

## Scope and remaining verification

The GitHub tree has been checked for the `.gitmodules` file and submodule pointer. The submodule itself is not expanded into ordinary files in the D’Lice repository, and this session has not performed a fresh local recursive clone or run the website build/test suite. Install the appropriate Superpowers plugin for the coding-agent harness separately if runtime skill activation is needed; a Git submodule alone does not activate agent skills automatically.

This integration does not change website colors, priority text, Supabase settings, Vercel settings, secrets, billing plans, or production deployment. Do not merge the pull request or deploy without Owner approval and required checks.
