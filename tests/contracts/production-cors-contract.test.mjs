import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const source = await readFile("supabase/functions/dlice-orders/index.ts", "utf8");

test("production CORS allowlist is exact and has no fallback origin", () => {
  assert.match(source, /new Set\(\[\s*"https:\/\/dlice\.vercel\.app",\s*"https:\/\/dlice-landing-page\.vercel\.app"\s*\]\)/);
  assert.match(source, /origin && allowedOrigins\.has\(origin\)[\s\S]{0,80}Access-Control-Allow-Origin/);
  assert.match(source, /"Vary": "Origin"/);
  assert.doesNotMatch(source, /"Access-Control-Allow-Origin"\s*:\s*"https?:\/\//);
});

test("foreign-origin preflight and POST requests fail closed", () => {
  assert.match(source, /if \(req\.method === "OPTIONS"\)[\s\S]{0,180}!isAllowedOrigin\(origin\)[\s\S]{0,100}403/);
  assert.match(source, /if \(origin && !allowedOrigins\.has\(origin\)\) return fail\([^\n]+403, origin\)/);
});

test("requests without Origin do not receive a fallback ACAO header", () => {
  assert.match(source, /const isAllowedOrigin = \(origin: string \| null\) => !origin \|\| allowedOrigins\.has\(origin\)/);
  assert.match(source, /origin && allowedOrigins\.has\(origin\) \? \{ "Access-Control-Allow-Origin": origin \} : \{\}/);
});
