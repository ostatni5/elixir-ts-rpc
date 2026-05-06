# examples/basic

A minimal end-to-end demo: a React SPA hitting an Elixir Plug backend using
cookie session auth, with TypeScript types generated from Elixir `@spec`s.

## Quick start

```bash
cd examples/basic
./run.sh
# open http://localhost:5173
```

Credentials: `alice / wonderland` (admin) or `bob / builder` (user).

## Manual start (without run.sh)

From `examples/basic`:

1. Build and generate:

   ```bash
   (cd server && mix deps.get && mix compile)
   npm install --prefix ../..
   npm run rpc:gen --workspace=@examples/basic-client
   ```

2. Start the Elixir server on `:4001` (leave this terminal running):

   ```bash
   (cd server && mix run --no-halt)
   ```

3. In a second terminal, start Vite and open `http://localhost:5173`:

   ```bash
   npm run dev --workspace=@examples/basic-client
   ```

## Architecture

```text
Browser (localhost:5173)
  └─ Vite dev server
       ├─ /auth/* → proxy → Elixir Plug (localhost:4001)
       ├─ /rpc/*  → proxy → Elixir Plug (localhost:4001)
       └─ static assets (React SPA)

Elixir Plug pipeline (BasicServer.Endpoint):
  Plug.Logger
  → Plug.Session (cookie store, SameSite=Lax)
  → :fetch_session
  → BasicServer.AuthPlug       ← POST /auth/login + /auth/logout
  → RpcElixir.Plug             ← handles /rpc/* routes
       → BasicServer.Router
            auth.me       (middleware: RequireUser)
            users.list    (middleware: RequireUser)
            users.get     (middleware: RequireUser)
            users.update  (middleware: RequireUser)
            users.delete  (middleware: RequireUser)
```

## Session and cookies

Requests go same-origin via the Vite proxy (`/auth` and `/rpc` both target
`http://localhost:4001`). Because the browser sees only `localhost:5173` and
the session cookie uses `SameSite=Lax`, no CORS headers are needed.

## Why login/logout are plain endpoints, not RPC procedures

RPC handlers return values. They cannot write to the response (no header,
cookie, or session mutation). Login and logout both need to mutate the session
cookie, so they live as plain Plug routes in `BasicServer.AuthPlug` at
`POST /auth/login` and `POST /auth/logout`.

`auth.me` stays an RPC procedure because it only *reads* the session. That
fits the typed RPC contract cleanly and benefits from the codegen.

## Handlers and compile-time spec validation

`RpcElixir.Router` validates `@spec` signatures inside `__before_compile__`.
By default it reads them from the handler's BEAM file, which forces handlers
into a separate Mix `path:` dep so their BEAMs are on disk before the router
compiles.

This demo avoids the split. Each handler module does `use RpcElixir.Handler`,
which captures spec ASTs into a `__rpc_specs__/0` accessor at handler-compile
time. The router calls that accessor instead of reading the BEAM, and the
function-call edge forces the parallel compiler to fully compile each handler
before the router's `__before_compile__` runs, so handlers and router can
live in the same Mix project.

## Regenerating TypeScript types

```bash
cd examples/basic/server
mix deps.get && mix compile
mix rpc.gen.ts --router BasicServer.Router --out ../client/src/rpc.gen.ts
```

Or via the npm script:

```bash
npm run rpc:gen --workspace=@examples/basic-client
```

### Watch mode

To regenerate automatically whenever an Elixir source file changes, run the
`rpc.gen.ts.watch` Mix task (it recompiles first, so `@spec` edits are picked
up):

```bash
npm run rpc:gen:watch --workspace=@examples/basic-client
```

This relies on the `:file_system` dev dependency already declared in the
server's `mix.exs`.

## Project structure

```
examples/basic/
  run.sh                   boot backend + Vite dev server
  server/                  Elixir Plug server (Mix project)
    lib/basic_server/
      application.ex       starts Cowboy on :4001
      endpoint.ex          Plug pipeline
      auth_plug.ex         POST /auth/login + /auth/logout (session writes)
      root_plug.ex         injects secret_key_base
      router.ex            RpcElixir.Router (auth.me, users.list/get/update/delete)
      users.ex             in-memory user store
      handlers/auth.ex     use RpcElixir.Handler - captures @spec for router
      handlers/users.ex
      middleware/require_user.ex
  client/                  Vite + React SPA
    src/rpc.gen.ts         GENERATED (commit for reproducibility)
    src/rpc.ts             creates the typed client
    src/App.tsx            login form, user list, logout
```

## What this demo proves

- `RpcElixir.Plug` handles HTTP transport with cookie session integration
- `BasicServer.Middleware.RequireUser` (app-level) loads users from session via `BasicServer.Users.get/1`
- `@spec` types flow from Elixir to TypeScript via codegen - no hand-written TypeScript types
- Typed errors round-trip: `users.update` returns a typed error union, and the SPA
  discriminates it with the per-procedure `rpc.users.update.isError` guard, then
  `isMiddlewareError` for the auth path within it, plus `isTransportError` for
  client-synthesized failures (see `App.tsx`)
- The Vite proxy pattern makes same-site cookies work without CORS configuration
- Cookie auth round-trip: login → session → protected procedure → logout
