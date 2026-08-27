# Playground

An in-browser playground for `elixir-ts-rpc`. Edit an Elixir `@spec` on the left,
watch the generated TypeScript client change on the right. There is no server and
no build step in the loop: `RpcElixir.Codegen.generate/1` itself runs in the tab,
as Elixir compiled to WebAssembly via [Popcorn](https://popcorn.swmansion.com).

The third pane runs Monaco's TypeScript language service against the generated
client, so hovers, completions, and diagnostics all come from your Elixir specs.
The **Guided tour** button walks through that, including following a generated
method's source link back to the handler, and renaming a field to watch the
TypeScript break.

## Toolchain

Popcorn 0.3.3 compares OTP and Elixir versions as exact strings and raises on
anything else, so this example pins **OTP 26.0.2 / Elixir 1.17.3** in
`.tool-versions` — deliberately different from the repo root. With `asdf` or
`mise` installed, entering this directory is enough.

## Run it

```sh
mix deps.get
cd assets && npm install && cd ..

# Cook the .avm bundle. `start_module` is only read from this call, never from
# config.exs, where Popcorn silently ignores it.
mix run -e 'Popcorn.cook(start_module: Playground.Server)'

cd assets && node build.mjs && cd ..
node serve.mjs dist 8099
```

Then open <http://localhost:8099>. First boot takes a few seconds: the bundle is
~7.7MB (~3.6MB gzipped) and the Popcorn runtime has to start before the first
generate.

After changing `lib/playground/server.ex` re-run the `cook` step; after changing
anything under `assets/` just re-run `node build.mjs`.

`serve.mjs` is not incidental. Popcorn needs `SharedArrayBuffer`, which requires
the COOP/COEP headers it sets, and Monaco's stylesheet is dropped by the browser
unless served as `text/css`.

## Deployment

Hosted on Netlify, because the Popcorn runtime needs `SharedArrayBuffer` and so
the response must carry COOP/COEP headers. GitHub Pages cannot set headers, which
is why this does not live alongside the docs site.

Netlify only *hosts*. The bundle is built by
`.github/workflows/deploy-playground.yml`, which pins OTP 26.0.2 / Elixir 1.17.3
through `setup-beam` and uploads the finished `dist/`. Netlify's own image would
have to compile Erlang from source to reach those exact versions, which does not
fit a build window.

One-time setup:

1. Create an empty Netlify site — **do not connect it to this Git repository.**
   With Git integration on, Netlify would run its own build, find no `dist/`, and
   publish an empty site over a good deploy.
2. Add two repository secrets: `NETLIFY_AUTH_TOKEN` (a personal access token) and
   `NETLIFY_SITE_ID` (the site's API ID).

Deploys then run on pushes to `main` that touch `examples/playground/` or
`apps/rpc_elixir/`, and can be triggered manually from the Actions tab.

To deploy by hand from a checkout:

```sh
./build.sh --production
npx netlify-cli deploy --prod --dir=dist
```

### The smoke test

The workflow deploys a draft, drives it with a real browser, and only then
promotes it. `assets/smoke.mjs` boots the deployed page in headless Chromium and
fails unless the first generation settles at two procedures:

```sh
node serve.mjs dist 8099 &
npx playwright install chromium   # once
node assets/smoke.mjs http://localhost:8099/
```

This is not belt-and-braces. Codegen runs inside AtomVM here, which has no `:re`
and no `ets:select`, so a library change that reintroduces either one still cooks
a valid `.avm` that still contains `RpcElixir.Codegen`. Every structural check in
the workflow stays green and the break appears only when a browser calls it.
`playwright` is in `assets/package.json` for this reason alone; it is not part of
the bundle.

### The tour video

The docs site embeds a recording of the guided tour, next to the link to the
live thing. `assets/record-tour.mjs` produces it, against a local build:

```sh
node serve.mjs dist 8099 &
node assets/record-tour.mjs http://localhost:8099/ ../../docs/public/playground-tour.mp4
```

It presses the button and stops when the tour closes itself, so re-recording
after a tour change is one command. ffmpeg trims the wasm boot off the front,
encodes h264, and writes the poster frame beside the video. Recording happens at
CSS pixel size, so asking Playwright for a video larger than the viewport pads
the frame grey instead of supersampling it.

## How it fits together

`lib/playground/server.ex` registers itself with `Popcorn.Wasm.ready/1` and loops
on messages from JS. Each request carries Elixir source; it compiles it with
`Code.compile_string/1`, finds the module exporting `__procedures__/0`, and hands
that to the codegen.

Compiling the router at runtime is the requirement, not a shortcut.
`Code.Typespec.fetch_specs/1` needs reachable debug info, and modules packed into
the `.avm` have none — `:code.which/1` returns `[]` with no filesystem. Every
failure is caught and returned as data, because an uncaught raise takes the VM
down and forces a page reload.

## This is a simulation

The codegen is the real one, but it runs in a browser sandbox, so some things
behave differently than they would in a real project. The app says so too, behind
the **⚠ Simulated environment** button.

- **Nothing is actually called.** No server sits behind `createRpcClient`. You get
  the types, not a working RPC round trip.
- **One buffer is the whole world.** Handlers, routers and custom types must all be
  defined in the left pane. Specs that reference modules from a real app (Ecto
  schemas, middleware, `RpcElixir.CustomType` implementations in other files)
  cannot resolve.
- **Object field order can differ** from `mix rpc.gen.ts`. The IR holds fields in a
  map and the renderer iterates it, so order follows the VM: the host BEAM iterates
  small maps in insertion order, this one sorts them. Field order is not meaningful
  in TypeScript, but the output is not byte-identical.
- **The client types are a stub.** The consumer pane checks against a small
  hand-written declaration of `@elixir-ts-rpc/client` (in `assets/index.js`), not
  the published package, so its shapes can drift.
- **Source links point at the editor, not a file.** Real generation puts an
  absolute `file://` link to the handler line in the JSDoc, and your editor opens
  it. Here the handler is the left pane, so the link names that buffer and the
  page intercepts it to reveal the line.
- **Elixir 1.17.3 only**, because Popcorn pins it exactly. `FromInferred` needs
  1.19 set-theoretic types, so that backend cannot be demonstrated.
- **Slower.** A regenerate takes seconds in wasm; natively it is part of a normal
  compile.

## Not enabled: treeshake

Popcorn's treeshaker recompiles from Core Erlang, which destroys Elixir
typespecs — `fetch_specs` starts returning `{:ok, []}` and codegen emits an empty
client with no error at all. It also drops `:elixir_parser` and `:erl_eval`,
which runtime compilation needs. `treeshake: false` is the default; leave it.

## Credits

Running Elixir in the browser here is entirely the work of
[Popcorn](https://popcorn.swmansion.com) by
[Software Mansion](https://swmansion.com) (Apache-2.0), which compiles and ships
the BEAM-compatible runtime this example depends on. This playground only supplies
a router and a couple of editors on top of it.

Editors are [Monaco](https://github.com/microsoft/monaco-editor) (MIT).
