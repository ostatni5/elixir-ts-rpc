// Boots the deployed playground in a real browser and fails if the first
// generation does not land. Usage: node smoke.mjs https://deploy-url/
//
// The bundle-level checks in the deploy workflow cannot see this class of
// failure. Codegen runs inside AtomVM here, which lacks `:re` and `ets:select`,
// so a library change that reintroduces either one still cooks a valid .avm
// containing RpcElixir.Codegen and still passes every `test -f` and grep. It
// breaks only once a browser calls it. This is the check that notices.
import { chromium } from "playwright";

const url = process.argv[2];
if (!url) {
  console.error("usage: node smoke.mjs <url>");
  process.exit(2);
}

// Cold wasm boot plus a first generation, on a CI runner without a warm cache.
const READY_TIMEOUT_MS = 120_000;
const EXPECTED_PROCEDURES = 2;

const browser = await chromium.launch();
const page = await browser.newPage();

const log = [];
page.on("console", (m) => log.push(`[${m.type()}] ${m.text()}`));
page.on("pageerror", (e) => log.push(`[pageerror] ${e.message}`));

const fail = async (message) => {
  console.error(`smoke: ${message}`);
  if (log.length > 0) console.error(`\npage output:\n${log.join("\n")}`);
  await page.screenshot({ path: "smoke-failure.png", fullPage: true }).catch(() => {});
  await browser.close();
  process.exit(1);
};

await page.goto(url, { waitUntil: "domcontentloaded" });

// Without this the Popcorn runtime cannot get a SharedArrayBuffer and nothing
// else below can pass, so report it as its own failure rather than a timeout.
if (!(await page.evaluate(() => self.crossOriginIsolated))) {
  await fail("page is not cross-origin isolated, so SharedArrayBuffer is unavailable");
}

// `#status` carries the settled result: class `ok` only after a generation
// returned and its TypeScript reached the editor. Class `err` covers a failed
// boot, a codegen raise, and a dead call, so wait for either and report which.
const status = page.locator("#status");
try {
  await status.and(page.locator(".ok, .err")).waitFor({ timeout: READY_TIMEOUT_MS });
} catch {
  await fail(
    `no generation settled within ${READY_TIMEOUT_MS}ms (status: "${await status.textContent()}")`,
  );
}

const text = (await status.textContent())?.trim() ?? "";
const classes = (await status.getAttribute("class")) ?? "";

if (classes.includes("err")) {
  const detail = (await page.locator("#error").textContent())?.trim();
  await fail(`playground reported an error: "${text}"${detail ? `\n${detail}` : ""}`);
}

const procedures = Number(text.match(/^(\d+) procedures/)?.[1]);
if (procedures !== EXPECTED_PROCEDURES) {
  await fail(`expected ${EXPECTED_PROCEDURES} procedures from the default source, got "${text}"`);
}

console.log(`smoke: ok — ${text}`);
await browser.close();
