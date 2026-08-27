import { copyFile, mkdir } from "node:fs/promises";
import { popcorn } from "@swmansion/popcorn/esbuild";
import * as esbuild from "esbuild";

await mkdir("../dist", { recursive: true });
await copyFile("index.html", "../dist/index.html");

// Sourcemaps for these bundles are larger than the bundles themselves
// (ts.worker alone is ~18MB of map), so production ships without them.
const production = process.env.NODE_ENV === "production";

const shared = {
  bundle: true,
  format: "esm",
  sourcemap: !production,
  minify: production,
  loader: { ".ttf": "file", ".woff": "file", ".woff2": "file" },
  logOverride: { "direct-eval": "silent" },
};

// Monaco's workers are classic-ish standalone bundles; keep them out of the app graph.
await esbuild.build({
  ...shared,
  entryPoints: {
    "editor.worker": "monaco-editor/editor/editor.worker.js",
    "ts.worker": "monaco-editor/language/typescript/ts.worker.js",
  },
  outdir: "../dist",
});

await esbuild.build({
  ...shared,
  entryPoints: ["index.js"],
  outfile: "../dist/index.js",
  plugins: [popcorn({ bundlePaths: ["../dist/wasm/bundle.avm"] })],
});
