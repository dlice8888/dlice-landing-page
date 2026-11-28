#!/usr/bin/env bash
set -euo pipefail

# Generate the timestamped migration with Supabase CLI, never hand-pick its name.
supabase --version
supabase init --help >/dev/null
if [[ ! -f supabase/config.toml ]]; then
  supabase init
fi
supabase migration --help >/dev/null
supabase migration new --help >/dev/null
supabase db reset --help >/dev/null
supabase test db --help >/dev/null

draft="docs/implementation/sql/BRANCH_OPERATIONS_CONCRETE_PERSISTENCE_DRAFT.sql"
test -s "$draft"
mkdir -p supabase/migrations
before="$(find supabase/migrations -maxdepth 1 -type f -name '*_branch_operations_persistence.sql' -print | sort)"
supabase migration new branch_operations_persistence
after="$(find supabase/migrations -maxdepth 1 -type f -name '*_branch_operations_persistence.sql' -print | sort)"
created="$(comm -13 <(printf '%s\n' "$before") <(printf '%s\n' "$after") | sed '/^$/d')"
if [[ "$(printf '%s\n' "$created" | sed '/^$/d' | wc -l | tr -d ' ')" != "1" ]]; then
  echo "Expected exactly one new CLI-generated migration file; found: $created" >&2
  exit 1
fi
cp "$draft" "$created"

# Start/replay only the disposable local Supabase stack. This script must never
# receive a linked staging/production project or run db push.
supabase start
supabase db reset
supabase test db

echo "Branch Operations migration replay and pgTAP passed: $created"
