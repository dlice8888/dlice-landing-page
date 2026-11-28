#!/usr/bin/env bash
set -euo pipefail

# Replays the already committed CLI-generated Branch Operations migration only
# against a local disposable stack. Never link or push to a hosted project.
supabase --version
supabase init --help >/dev/null
if [[ ! -f supabase/config.toml ]]; then
  supabase init --force
fi
supabase db reset --help >/dev/null
supabase test db --help >/dev/null

migration="supabase/migrations/20261128024514_branch_operations_persistence.sql"
draft="docs/implementation/sql/BRANCH_OPERATIONS_CONCRETE_PERSISTENCE_DRAFT.sql"
test -s "$migration"
test -s "$draft"
cmp -s "$migration" "$draft"

supabase start --exclude inbucket
supabase db reset
supabase test db
supabase stop --no-backup

echo "Branch Operations official migration replay and pgTAP passed: $migration"
