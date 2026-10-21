#!/usr/bin/env node
/**
 * Staging browser smoke: desktop + mobile responsive/login shell.
 * Does not submit credentials or mutate ERP data.
 * Required: PREVIEW_URL (must be the staging Vercel Preview, never production).
 */
import { chromium, devices } from "playwright";
import assert from "node:assert/strict";

const base = process.env.PREVIEW_URL?.replace(/\/$/, "");
if (!base) {
  console.error("BLOCKED: PREVIEW_URL is required.");
  process.exit(2);
}
const parsed = new URL(base);
if (!parsed.hostname.endsWith(".vercel.app") || parsed.hostname === "dlice.vercel.app") {
  console.error("REFUSED: PREVIEW_URL must be a Vercel Preview host, not production.");
  process.exit(2);
}

const browser = await chromium.launch({ headless: true });
const results = [];
async function check(label, run) {
  try {
    await run();
    results.push({ label, status: "PASS" });
    console.log("PASS", label);
  } catch (error) {
    results.push({ label, status: "FAIL" });
    console.error("FAIL", label, error instanceof Error ? error.message : String(error));
  }
}

try {
  const desktop = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  await check("BROWSER-DESKTOP-ERP-LOAD", async () => {
    const response = await desktop.goto(`${base}/erp.html`, { waitUntil: "domcontentloaded", timeout: 45000 });
    assert.ok(response && response.status() < 400, `HTTP ${response?.status()}`);
    assert.match(await desktop.title(), /D’Lice.*Operasional.*POS/i);
    await desktop.locator("#username").waitFor({ state: "visible", timeout: 15000 });
    await desktop.locator("#password").waitFor({ state: "visible" });
    assert.equal(await desktop.locator("#username").getAttribute("autocomplete"), "username");
    assert.equal(await desktop.locator("#password").getAttribute("type"), "password");
    const overflow = await desktop.evaluate(() => document.documentElement.scrollWidth > window.innerWidth);
    assert.equal(overflow, false, "unexpected horizontal overflow at 1440px");
  });

  const mobile = await browser.newPage({ ...devices["Pixel 7"] });
  await check("BROWSER-MOBILE-ERP-LOAD", async () => {
    const response = await mobile.goto(`${base}/erp.html`, { waitUntil: "domcontentloaded", timeout: 45000 });
    assert.ok(response && response.status() < 400, `HTTP ${response?.status()}`);
    await mobile.locator("#username").waitFor({ state: "visible", timeout: 15000 });
    await mobile.locator("#password").waitFor({ state: "visible" });
    const viewport = await mobile.evaluate(() => ({ width: window.innerWidth, scrollWidth: document.documentElement.scrollWidth }));
    assert.ok(viewport.width > 0);
    assert.ok(viewport.scrollWidth <= viewport.width + 1, `horizontal overflow: ${JSON.stringify(viewport)}`);
    const tapTarget = await mobile.locator("button").first().evaluate((el) => {
      const r = el.getBoundingClientRect();
      return { width: r.width, height: r.height };
    });
    assert.ok(tapTarget.height >= 40, `first button target too small: ${JSON.stringify(tapTarget)}`);
  });

  const homepage = await browser.newPage({ viewport: { width: 390, height: 844 } });
  await check("BROWSER-MOBILE-HOMEPAGE", async () => {
    const response = await homepage.goto(base, { waitUntil: "domcontentloaded", timeout: 45000 });
    assert.ok(response && response.status() < 400, `HTTP ${response?.status()}`);
    assert.match(await homepage.title(), /D’Lice/i);
    const overflow = await homepage.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
    assert.equal(overflow, false, "homepage has horizontal overflow at mobile width");
  });
} finally {
  await browser.close();
}

const failed = results.filter((x) => x.status === "FAIL");
console.log(`Browser summary: ${results.length - failed.length} PASS, ${failed.length} FAIL.`);
if (!results.length || failed.length) process.exit(1);
