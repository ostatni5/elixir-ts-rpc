# examples/phoenix

Typed RPC bolted onto a **real Phoenix app**, reusing Phoenix's own
`mix phx.gen.auth` authentication **and** its CSRF protection. Adding
`elixir-ts-rpc` to a conventional Phoenix app is a few lines of glue — you write
no auth code and don't roll a second CSRF mechanism.

Where [examples/basic](../basic) is a minimal Plug server with a hand-rolled login
endpoint, this is a stock Phoenix 1.8 app (SQLite, LiveView auth UI, DB-backed
session tokens, email confirmation, password reset) with an RPC router on top.

## Quick start

```bash
cd examples/phoenix
./run.sh
# open http://localhost:4000
# log in with the seeded demo user: demo@example.com / demopassword123
```

`run.sh` sets up SQLite, seeds the demo user, boots Phoenix on `:4000`, and starts
Vite on `:5173`. You browse Phoenix; Vite only serves the React bundle for HMR.

> **Scope:** local development only. Production would `vite build` the client and
> let Phoenix serve the hashed manifest — intentionally left out to keep the focus
> on the RPC + auth + CSRF integration.

## How the integration works

### Auth — reuse Phoenix's `current_scope`

Phoenix's generated `fetch_current_scope_for_user` plug runs on the RPC route, and
a one-line context builder lifts the scope into the RPC context:

```elixir
# rpc/context.ex
def build(conn),
  do: %RpcElixir.Context{assigns: %{current_scope: conn.assigns[:current_scope]}}
```

A tiny middleware authorizes against it — halting with an `:unauthorized`
`RpcError` when there's no user — with no session parsing or user lookup of its own.

Login/logout stay in Phoenix's controllers because RPC handlers can't write to the
response — see [how it works](https://ostatni5.github.io/elixir-ts-rpc/guide/how-it-works).
`auth.me` is RPC because it only *reads* the scope. `counter.adjust` shows the
other side: handlers *can* write to the database (only the HTTP response is
off-limits), so a state-changing procedure fits the RPC contract fine.

### CSRF — reuse Phoenix's `protect_from_forgery`

The RPC route goes through a pipeline that includes Phoenix's CSRF plug, and
`RpcElixir.Plug`'s own content-type CSRF defense is turned off — one mechanism,
not two:

```elixir
# router.ex
pipeline :rpc do
  plug :accepts, ["json"]
  plug :fetch_session
  plug :protect_from_forgery            # Phoenix's CSRF — reused
  plug :fetch_current_scope_for_user    # Phoenix's auth — reused
end

forward "/rpc", RpcElixir.Plug,
  router: PhoenixExampleWeb.RpcRouter,
  path_prefix: "/rpc",
  ctx_builder: &PhoenixExampleWeb.Rpc.Context.build/1,
  require_content_type: false           # Phoenix owns CSRF
```

For JSON, `Plug.CSRFProtection` validates the `x-csrf-token` header. The SPA reads
the token from the standard `<meta name="csrf-token">` tag and sends it on every
call, so Phoenix serves the SPA's HTML shell (`SpaController` + `SpaHTML`) while
Vite bundles the React app — the standard Vite *backend-integration* setup. A
`POST` to `/rpc/*` without the token is rejected with `403` by Phoenix.

### Types — identical to a plain Plug app

The `:elixir_ts_rpc` compiler (in `mix.exs` `compilers:`, configured in
`config/config.exs`) regenerates `client/src/rpc.gen.ts` from the router's
`@spec`s on every `mix compile`, which Phoenix runs on boot and reload. No
SPA-side codegen script. `DateTime` fields cross the wire as epoch-millis
(`UnixMillis` alias).

## Project structure

```
examples/phoenix/
  run.sh                       boot SQLite + Phoenix (:4000) + Vite (:5173)
  server/                      stock phx.new + phx.gen.auth app, plus:
    config/config.exs            +:elixir_ts_rpc codegen config
    lib/phoenix_example_web/
      router.ex                  +:rpc pipeline + forward + SPA route
      rpc_router.ex              RpcElixir.Router (auth.me, users.list/get, counter.get/adjust)
      rpc/context.ex             lifts current_scope into the RPC context
      rpc/middleware/require_user.ex
      rpc/handlers/{auth,users,counter}.ex
      controllers/spa_controller.ex + spa_html.ex   serve the SPA shell
  client/                      Vite + React SPA (backend-integration mode)
    src/rpc.gen.ts               GENERATED on `mix compile` (gitignored)
    src/rpc.ts                   typed client with the CSRF header
```

## What this example proves

- RPC authenticates against Phoenix's session-derived `current_scope` — zero auth
  code written for RPC.
- Phoenix's `protect_from_forgery` guards the RPC route; `RpcElixir.Plug`'s own
  CSRF defense is disabled — one CSRF mechanism, Phoenix's.
- `@spec` → TypeScript codegen works exactly as in a plain Plug app, owned by the
  Phoenix compile step.
- The write path works: `counter.adjust` validates input, persists to the
  database, and returns a typed result the SPA renders live.

## Tests

```bash
cd server && mix test
```

`test/.../rpc_integration_test.exs` drives the real pipeline: an unauthenticated
call returns a typed `unauthorized`; an authenticated call returns real database
users.
