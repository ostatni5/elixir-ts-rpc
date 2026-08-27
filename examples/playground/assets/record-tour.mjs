// Records the guided tour as the video the docs site embeds.
// Usage: node record-tour.mjs <url> <out.mp4>   (also writes <out>.jpg, its poster)
//
// The tour is deterministic (see tour.js), so this is a replay rather than a
// take: boot the page, wait for the first generation to settle, press the
// button, stop when the tour closes itself. Playwright records raw VP8, which
// ffmpeg then trims and re-encodes, because the recording starts at page load
// and nobody needs to watch a wasm runtime boot.

import { spawnSync } from "node:child_process";
import { rm } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { chromium } from "playwright";

const url = process.argv[2];
const out = process.argv[3];
if (!url || !out?.endsWith(".mp4")) {
  console.error("usage: node record-tour.mjs <url> <out.mp4>");
  process.exit(2);
}

// A cold wasm boot on an unwarmed cache, then the tour's own scripted holds.
const READY_TIMEOUT_MS = 120_000;
const TOUR_TIMEOUT_MS = 240_000;
// The viewport is short on purpose: the panes hold little enough that 900px
// leaves a third of the frame empty, and the video has to sit in a docs column.
//
// The recording is CSS-pixel sized, so asking for a video larger than the
// viewport does not supersample: Playwright pastes the frame into the corner of
// an oversized canvas and pads the rest grey. Keep the two equal, and keep the
// viewport narrow, since the editor font is a fixed size and every pixel of
// viewport width shrinks the text once a docs column scales the video down.
const VIEWPORT = { width: 1440, height: 760 };
// Kept before the click so the opening frame is a settled editor, not a jump cut.
const LEAD_IN_MS = 900;

const ffmpeg = (args) => {
  const { status, stderr } = spawnSync("ffmpeg", args, { encoding: "utf8" });
  if (status !== 0) {
    console.error(stderr);
    throw new Error(`ffmpeg exited ${status}`);
  }
};

const browser = await chromium.launch();
const context = await browser.newContext({
  viewport: VIEWPORT,
  recordVideo: { dir: dirname(resolve(out)), size: VIEWPORT },
});
const page = await context.newPage();
const recordingStartedAt = Date.now();

const fail = async (message) => {
  console.error(`record-tour: ${message}`);
  await context.close();
  await browser.close();
  process.exit(1);
};

await page.goto(url, { waitUntil: "domcontentloaded" });

if (!(await page.evaluate(() => self.crossOriginIsolated))) {
  await fail("page is not cross-origin isolated, so the runtime cannot boot");
}

const status = page.locator("#status");
try {
  await status.and(page.locator(".ok")).waitFor({ timeout: READY_TIMEOUT_MS });
} catch {
  await fail("the first generation never settled");
}

await page.waitForTimeout(1500);
const clickedAt = Date.now();
await page.locator("#tour-btn").click();

// The button carries `.running` for exactly as long as the tour is open, and
// the tour closes itself after its last step.
const running = page.locator("#tour-btn.running");
try {
  await running.waitFor({ timeout: 15_000 });
  await running.waitFor({ state: "detached", timeout: TOUR_TIMEOUT_MS });
} catch {
  await fail("the tour did not run to completion");
}

await page.waitForTimeout(1200);

const video = page.video();
await context.close();
const raw = await video.path();
await browser.close();

const trimSeconds = Math.max(0, (clickedAt - recordingStartedAt - LEAD_IN_MS) / 1000);

ffmpeg([
  "-v",
  "error",
  "-ss",
  trimSeconds.toFixed(2),
  "-i",
  raw,
  "-an",
  "-c:v",
  "libx264",
  "-preset",
  "slow",
  "-crf",
  "20",
  "-pix_fmt",
  "yuv420p",
  "-movflags",
  "+faststart",
  "-y",
  resolve(out),
]);

// The poster is the frame a visitor stares at before pressing play, so take it
// from the first step rather than the blank opening.
ffmpeg([
  "-v",
  "error",
  "-ss",
  "2",
  "-i",
  resolve(out),
  "-frames:v",
  "1",
  "-q:v",
  "4",
  "-y",
  resolve(out.replace(/\.mp4$/, ".jpg")),
]);

await rm(raw, { force: true });
console.log(`record-tour: wrote ${out} (trimmed ${trimSeconds.toFixed(1)}s of boot)`);
