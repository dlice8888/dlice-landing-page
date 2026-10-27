import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const migration = await readFile(
  "supabase/migrations/20261027112330_explicit_deny_policies_server_only_tables.sql",
  "utf8",
);

const serverOnlyTables = [
  "backup_restore_runs",
  "branch_settings",
  "integration_connections",
  "integration_outbox",
  "inventory_waste_events",
  "kitchen_ticket_items",
  "kitchen_tickets",
  "offline_sync_receipts",
  "order_stock_consumptions",
  "pos_idempotency_requests",
  "product_modifiers",
  "recipe_substitutions",
  "shift_handover_records",
  "tenant_invites",
  "tenant_memberships",
  "tenants",
  "warehouses",
];

for (const table of serverOnlyTables) {
  const escaped = table.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  assert.match(
    migration,
    new RegExp(
      `create policy deny_direct_client_access on public\\.${escaped}\\s+for all to anon, authenticated\\s+using \\(false\\)\\s+with check \\(false\\)`,
      "i",
    ),
    `Expected explicit deny policy for public.${table}`,
  );
  assert.match(
    migration,
    new RegExp(`revoke all on table public\\.${escaped} from anon, authenticated`, "i"),
    `Expected direct client privileges revoked for public.${table}`,
  );
}

assert.match(migration, /enable row level security/i);
assert.match(migration, /server-only/i);
console.log(`PASS: explicit deny policies and revoked client grants for ${serverOnlyTables.length} server-only tables.`);
