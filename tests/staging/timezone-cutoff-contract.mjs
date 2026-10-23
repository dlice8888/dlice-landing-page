#!/usr/bin/env node
/**
 * Deterministic timezone/cutoff contract checks for staging.
 * These tests validate the 18:00 local-time boundary and the migration's use
 * of each branch timezone. Live database checkout probes remain a separate gate.
 */
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const migration = await readFile(new URL("../../supabase/migrations/20261021151246_branch_timezone_checkout_cutoff.sql", import.meta.url), "utf8");
assert.match(migration, /v_now_local\s*:=\s*now\(\)\s+at\s+time\s+zone\s+v_timezone/i, "checkout must derive local time from the selected branch timezone");
assert.match(migration, /v_requested_date\s*=\s*v_now_local::date\s+and\s+v_now_local::time\s*>=\s*time\s*'18:00'/i, "same-day checkout cutoff must reject at/after 18:00 local time");

function localClock(iso, timeZone) {
  const parts = new Intl.DateTimeFormat("en-GB", {
    timeZone, hour: "2-digit", minute: "2-digit", second: "2-digit", hourCycle: "h23",
  }).formatToParts(new Date(iso));
  const get = (name) => parts.find((part) => part.type === name)?.value;
  return `${get("hour")}:${get("minute")}:${get("second")}`;
}

const cases = [
  { label: "WIB", zone: "Asia/Jakarta", before: "2026-10-23T10:59:59Z", cutoff: "2026-10-23T11:00:00Z" },
  { label: "WITA", zone: "Asia/Makassar", before: "2026-10-23T09:59:59Z", cutoff: "2026-10-23T10:00:00Z" },
  { label: "WIT", zone: "Asia/Jayapura", before: "2026-10-23T08:59:59Z", cutoff: "2026-10-23T09:00:00Z" },
];
for (const c of cases) {
  assert.equal(localClock(c.before, c.zone), "17:59:59", `${c.label} must remain before cutoff one second before 18:00`);
  assert.equal(localClock(c.cutoff, c.zone), "18:00:00", `${c.label} must hit cutoff at 18:00`);
  console.log(`PASS TIMEZONE-CUTOFF-${c.label}: 17:59:59 allowed boundary; 18:00:00 cutoff boundary`);
}
console.log("PASS TIMEZONE-CUTOFF-CONTRACT: branch-local 18:00 rule verified for WIB/WITA/WIT.");
