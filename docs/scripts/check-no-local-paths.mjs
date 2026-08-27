// Guards the published site against leaking a path from whoever built it. The
// generated client's JSDoc carries handler source links, and the generator that
// writes them emits an absolute file:/// URI when given an output path. The docs
// fixture avoids that by construction; this checks the built output anyway,
// because the failure is silent and ships straight to GitHub Pages.
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";

const DIST = new URL("../.vitepress/dist/", import.meta.url).pathname;
const PATTERNS = [/file:\/\/\//, /\/(?:Users|home)\/[a-z]/i];

function* walk(dir) {
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry);
    if (statSync(full).isDirectory()) yield* walk(full);
    else yield full;
  }
}

const offenders = [];
for (const file of walk(DIST)) {
  if (!/\.(html|js|css|json|txt)$/.test(file)) continue;
  const text = readFileSync(file, "utf8");
  for (const pattern of PATTERNS) {
    const hit = pattern.exec(text);
    if (hit) offenders.push(`${file.slice(DIST.length)}: ${hit[0]}`);
  }
}

if (offenders.length > 0) {
  console.error("Local filesystem paths found in the built docs:");
  for (const line of offenders) console.error(`  ${line}`);
  process.exit(1);
}
console.log("docs output is free of local filesystem paths");
