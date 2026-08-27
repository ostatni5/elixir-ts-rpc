// Static server with COOP/COEP, which Popcorn's SharedArrayBuffer needs.
import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { extname, join, normalize } from "node:path";

const ROOT = process.argv[2];
const PORT = Number(process.argv[3] ?? 8099);
const TYPES = {
  ".html": "text/html", ".js": "text/javascript", ".mjs": "text/javascript",
  ".wasm": "application/wasm", ".avm": "application/octet-stream",
  ".map": "application/json", ".json": "application/json",
  // Browsers reject a stylesheet served with the wrong MIME type outright.
  ".css": "text/css", ".ttf": "font/ttf", ".woff": "font/woff", ".woff2": "font/woff2",
};

createServer(async (req, res) => {
  res.setHeader("Cross-Origin-Opener-Policy", "same-origin");
  res.setHeader("Cross-Origin-Embedder-Policy", "require-corp");
  res.setHeader("Cross-Origin-Resource-Policy", "same-origin");
  res.setHeader("Cache-Control", "no-store");
  // Inside the try because a malformed percent-escape makes decoding throw.
  try {
    const rel = normalize(decodeURIComponent(req.url.split("?")[0])).replace(/^(\.\.[/\\])+/, "");
    const path = join(ROOT, rel === "/" ? "index.html" : rel);
    const body = await readFile(path);
    res.writeHead(200, { "Content-Type": TYPES[extname(path)] ?? "application/octet-stream" });
    res.end(body);
  } catch {
    res.writeHead(404).end("not found");
  }
}).listen(PORT, () => console.log(`serving ${ROOT} on http://localhost:${PORT}`));
