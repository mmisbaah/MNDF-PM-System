import assert from "node:assert/strict";
import { mkdir, writeFile } from "node:fs/promises";
import { chromium } from "playwright";

const baseUrl = (process.env.ACCEPTANCE_BASE_URL || "http://127.0.0.1:3100").replace(/\/$/, "");
const loginId = process.env.ACCEPTANCE_LOGIN_ID;
const password = process.env.ACCEPTANCE_PASSWORD;
const outputDirectory = process.env.BROWSER_REGRESSION_OUTPUT || "output/browser-regression";
const browserChannel = process.env.BROWSER_CHANNEL || undefined;
assert.ok(loginId && password, "Dedicated dummy ACCEPTANCE_LOGIN_ID and ACCEPTANCE_PASSWORD are required");

await mkdir(outputDirectory, { recursive: true });
const startedAt = new Date();
const checks = [];
const failures = [];
let browser;
let page;

function pass(name) {
  checks.push({ name, status: "PASS" });
}

try {
  browser = await chromium.launch({ headless: true, channel: browserChannel });
  const context = await browser.newContext({
    viewport: { width: 390, height: 844 },
    locale: "en-MV",
    timezoneId: "Indian/Maldives",
  });
  page = await context.newPage();
  page.on("console", (message) => {
    if (message.type() === "error") failures.push(`browser console error: ${message.text().slice(0, 300)}`);
  });
  page.on("pageerror", (error) => failures.push(`uncaught page error: ${error.message.slice(0, 300)}`));
  page.on("response", (response) => {
    if (response.status() >= 500) failures.push(`server ${response.status()} response: ${new URL(response.url()).pathname}`);
  });

  await page.goto(baseUrl, { waitUntil: "networkidle" });
  assert.equal(await page.title(), "Performance Tracker");
  await page.getByLabel("Pilot login ID").fill(loginId);
  await page.getByLabel("Password").fill(password);
  await page.getByRole("button", { name: "Sign in" }).click();
  await page.getByRole("button", { name: "Sign out" }).waitFor({ timeout: 15_000 });
  await page.getByText("Loading tenant workspace...").waitFor({ state: "hidden", timeout: 15_000 });
  pass("dummy account signs in and tenant workspace finishes loading");

  const viewportOverflow = await page.evaluate(
    () => document.documentElement.scrollWidth - document.documentElement.clientWidth,
  );
  assert.equal(viewportOverflow, 0, "mobile page must not overflow horizontally");
  pass("390px mobile viewport has no page-level horizontal overflow");

  for (const tab of ["Overview", "Appraisals", "Activities", "Complaints", "Reports", "Absence & conduct"]) {
    const control = page.getByRole("button", { name: tab, exact: true });
    await control.scrollIntoViewIfNeeded();
    await control.click();
    assert.equal(await control.getAttribute("aria-current"), "page", `${tab} must expose its selected state`);
  }
  pass("primary workspace sections navigate and expose selected state");

  assert.equal(failures.length, 0, failures.join("; "));
  await page.getByRole("button", { name: "Sign out" }).click();
  await page.getByRole("button", { name: "Sign in" }).waitFor({ timeout: 10_000 });
  pass("sign-out returns to the login screen");
} catch (error) {
  if (page) await page.screenshot({ path: `${outputDirectory}/failure.png`, fullPage: true }).catch(() => undefined);
  failures.push(error instanceof Error ? error.message : String(error));
} finally {
  await browser?.close();
}

const result = {
  format: "performance-tracker-browser-regression-v1",
  status: failures.length ? "FAIL" : "PASS",
  baseOrigin: new URL(baseUrl).origin,
  startedAt: startedAt.toISOString(),
  finishedAt: new Date().toISOString(),
  checks,
  failures,
};
await writeFile(`${outputDirectory}/result.json`, `${JSON.stringify(result, null, 2)}\n`, "utf8");
console.log(JSON.stringify(result));
if (failures.length) process.exit(1);
