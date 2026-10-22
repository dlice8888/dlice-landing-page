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
if (!parsed.hostname.endsWith(".vercel.app") || ["dlice.vercel.app", "dlice-landing-page.vercel.app"].includes(parsed.hostname)) {
  console.error("REFUSED: PREVIEW_URL must be a Vercel Preview host, not production.");
  process.exit(2);
}

const browser = await chromium.launch({ headless: true });
const bypassSecret = process.env.VERCEL_AUTOMATION_BYPASS_SECRET;
const results = [];
async function configurePage(page) {
  if (bypassSecret) await page.setExtraHTTPHeaders({ "x-vercel-protection-bypass": bypassSecret });
}
async function assertNotVercelProtection(page) {
  const title = await page.title().catch(() => "");
  if (/login\s*[–-]\s*vercel/i.test(title)) {
    throw new Error("BLOCKED: Vercel Deployment Protection intercepted Preview. Configure Actions secret VERCEL_AUTOMATION_BYPASS_SECRET.");
  }
}
async function check(label, run) {
  try {
    await run();
    results.push({ label, status: "PASS" });
    console.log("PASS", label);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    const status = message.startsWith("BLOCKED:") ? "BLOCKED" : "FAIL";
    results.push({ label, status });
    console.error(status, label, message);
  }
}

try {
  const desktop = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  await configurePage(desktop);
  await check("BROWSER-DESKTOP-ERP-LOAD", async () => {
    const response = await desktop.goto(`${base}/erp.html`, { waitUntil: "domcontentloaded", timeout: 45000 });
    assert.ok(response && response.status() < 400, `HTTP ${response?.status()}`);
    await assertNotVercelProtection(desktop);
    assert.match(await desktop.title(), /D’Lice.*Operasional.*POS/i);
    await desktop.locator("#username").waitFor({ state: "visible", timeout: 15000 });
    await desktop.locator("#password").waitFor({ state: "visible" });
    assert.equal(await desktop.locator("#username").getAttribute("autocomplete"), "username");
    assert.equal(await desktop.locator("#password").getAttribute("type"), "password");
    const overflow = await desktop.evaluate(() => document.documentElement.scrollWidth > window.innerWidth);
    assert.equal(overflow, false, "unexpected horizontal overflow at 1440px");
  });

  const mobile = await browser.newPage({ ...devices["Pixel 7"] });
  await configurePage(mobile);
  await check("BROWSER-MOBILE-ERP-LOAD", async () => {
    const response = await mobile.goto(`${base}/erp.html`, { waitUntil: "domcontentloaded", timeout: 45000 });
    assert.ok(response && response.status() < 400, `HTTP ${response?.status()}`);
    await assertNotVercelProtection(mobile);
    await mobile.locator("#username").waitFor({ state: "visible", timeout: 15000 });
    await mobile.locator("#password").waitFor({ state: "visible" });
    const viewport = await mobile.evaluate(() => ({ width: window.innerWidth, scrollWidth: document.documentElement.scrollWidth }));
    assert.ok(viewport.width > 0);
    assert.ok(viewport.scrollWidth <= viewport.width + 1, `horizontal overflow: ${JSON.stringify(viewport)}`);
    const tapTarget = await mobile.locator("button:visible").first().evaluate((el) => {
      const r = el.getBoundingClientRect();
      return { width: r.width, height: r.height };
    });
    assert.ok(tapTarget.height >= 40, `first button target too small: ${JSON.stringify(tapTarget)}`);
  });

  const homepage = await browser.newPage({ viewport: { width: 390, height: 844 } });
  await configurePage(homepage);
  await check("BROWSER-MOBILE-HOMEPAGE", async () => {
    const response = await homepage.goto(base, { waitUntil: "domcontentloaded", timeout: 45000 });
    assert.ok(response && response.status() < 400, `HTTP ${response?.status()}`);
    await assertNotVercelProtection(homepage);
    assert.match(await homepage.title(), /D’Lice/i);
    const overflow = await homepage.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
    assert.equal(overflow, false, "homepage has horizontal overflow at mobile width");
  });
} finally {
  await browser.close();
}

const failed = results.filter((x) => x.status === "FAIL");
const blocked = results.filter((x) => x.status === "BLOCKED");
console.log(`Browser summary: ${results.filter((x) => x.status === "PASS").length} PASS, ${failed.length} FAIL, ${blocked.length} BLOCKED.`);
if (failed.length) process.exit(1);
if (!results.length || blocked.length) process.exit(2);
