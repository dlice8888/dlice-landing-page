import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const migrationPaths = [
  "../../supabase/migrations/20261128025950_20261126192455_crm_loyalty_financial_close.sql",
  "../../supabase/migrations/20261128030011_20261126192458_hr_workforce_payroll_finance.sql",
  "../../supabase/migrations/20261128030020_20261126192501_delivery_fulfillment_provider.sql",
  "../../supabase/migrations/20261128030021_20261126192504_franchise_expansion.sql",
  "../../supabase/migrations/20261128030024_20261126192506_procurement_supplier.sql",
  "../../supabase/migrations/20261128030026_20261126192509_bi_analytics.sql",
  "../../supabase/migrations/20261128030028_20261126192512_saas_tenant_billing.sql",
  "../../supabase/migrations/20261128030031_20261126192514_executive_command_center.sql",
];

function normalize(value) {
  return value.replace(/\s+/g, "").toLowerCase();
}

function signatureTypes(rawArgs) {
  return rawArgs.split(",").map((arg) => {
    const withoutDefault = arg.trim().replace(/\s+default\s+[\s\S]*$/i, "");
    const tokens = withoutDefault.split(/\s+/).filter(Boolean);
    if (tokens.length < 2) return "";
    const modeOffset = ["in", "out", "inout", "variadic"].includes(tokens[0].toLowerCase()) ? 2 : 1;
    return tokens.slice(modeOffset).join(" ").toLowerCase();
  }).filter(Boolean).join(",");
}

test("eight-domain migrations define unique public function signatures", () => {
  for (const relativePath of migrationPaths) {
    const sql = readFileSync(new URL(relativePath, import.meta.url), "utf8");
    const definitions = [...sql.matchAll(/create(?: or replace)? function public\.([a-z0-9_]+)\(([\s\S]*?)\)\s*returns/gi)];
    const signatures = definitions.map((match) => `${match[1]}(${signatureTypes(match[2])})`);
    assert.equal(new Set(signatures).size, signatures.length, `duplicate public function definition in ${relativePath}`);
  }
});

test("every eight-domain public function is revoked from clients and granted to service_role", () => {
  for (const relativePath of migrationPaths) {
    const sql = readFileSync(new URL(relativePath, import.meta.url), "utf8");
    const normalized = normalize(sql);
    const definitions = [...sql.matchAll(/create(?: or replace)? function public\.([a-z0-9_]+)\(([\s\S]*?)\)\s*returns/gi)];
    for (const match of definitions) {
      const signature = `${match[1]}(${signatureTypes(match[2])})`;
      assert.ok(
        normalized.includes(normalize(`revoke all on function public.${signature} from public,anon,authenticated;`)),
        `missing client EXECUTE revoke for ${signature} in ${relativePath}`,
      );
      assert.ok(
        normalized.includes(normalize(`grant execute on function public.${signature} to service_role;`)),
        `missing service_role EXECUTE grant for ${signature} in ${relativePath}`,
      );
    }
  }
});
