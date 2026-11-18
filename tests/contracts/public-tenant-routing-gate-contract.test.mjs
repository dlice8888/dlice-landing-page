import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const source = readFileSync("supabase/functions/dlice-orders/index.ts", "utf8");

test("public catalog and checkout remain closed until tenant routing is released", () => {
  assert.match(source, /const PUBLIC_TENANT_ROUTING_RELEASED = false;/);
  assert.match(source, /const PUBLIC_TENANT_ROUTING_REQUIRED_ACTIONS = new Set\(\[/);
  const gateStart = source.indexOf("if (!PUBLIC_TENANT_ROUTING_RELEASED && PUBLIC_TENANT_ROUTING_REQUIRED_ACTIONS.has(action))");
  assert.notEqual(gateStart, -1, "public tenant routing gate must be present");
  const gateEnd = source.indexOf("\n  }", gateStart);
  const gate = source.slice(gateStart, gateEnd + 4);
  assert.match(gate, /return fail\([\s\S]*?423[\s\S]*?origin/);
  for (const action of ["list-online-branches", "list-products", "create-order"]) {
    const actionIndex = source.indexOf(`"${action}"`, source.indexOf("PUBLIC_TENANT_ROUTING_REQUIRED_ACTIONS"));
    assert.ok(actionIndex > 0, `missing public tenant routing action ${action}`);
    assert.ok(actionIndex < gateStart, `action ${action} must be configured before the gate`);
    const handlerIndex = source.indexOf(`if (action === "${action}")`, gateStart);
    assert.ok(handlerIndex > gateStart, `handler for ${action} must remain behind the gate`);
  }
  assert.ok(gateStart < source.indexOf('if (action === "list-online-branches")'));
  assert.ok(gateStart < source.indexOf('if (action === "list-products")'));
  assert.ok(gateStart < source.indexOf('if (action === "create-order")'));
});
