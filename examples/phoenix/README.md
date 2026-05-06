# examples/phoenix

Typed RPC bolted onto a **real Phoenix app**, reusing Phoenix's own
`mix phx.gen.auth` authentication **and** Phoenix's CSRF protection. The point of
this example: adding `elixir-ts-rpc` to a conventional Phoenix app is a few lines
of glue. You write no auth code, and you don't roll a second CSRF mechanism.

Where [examples/basic](../basic) is a minimal Plug server with a hand-rolled login
endpoint, this example is the opposite: a stock Phoenix 1.8 app (SQLite,
LiveView auth UI, secure password hashing, DB-backed session tokens, email
confirmation, password reset) with an RPC router mounted on top.

## Quick start

```bash
cd examples/phoenix
./run.sh
# open http://localhost:4000
# log in with the seeded demo user: demo@example.com / demopassword123
```

`run.sh` sets up the SQLite database (no external service), seeds a demo user,
boots Phoenix on `:4000`, and starts the Vite dev server on `:5173`. You browse
Phoenix (`:4000`); Vite only serves the React bundle for HMR.

> **Scope:** this example targets local development. A production build would
> `vite build` the client and let Phoenix serve the hashed manifest assets
> (`SpaHTML` reads that manifest internally); wiring `vite build` into
> `mix assets.deploy` and reconciling it with `phx.digest` is intentionally left
> out to keep the focus on the RPC + auth + CSRF integration.

## The demo flow

1. Open `http://localhost:4000`. The React SPA calls `auth.me` over RPC, gets a
   typed `unauthorized` error, and shows a **Log in** link.
2. Click it. That's Phoenix's generated `/users/log-in` page (server-rendered,
   CSRF-protected, password + magic-link). Log in.
3. Phoenix redirects back to `/`. The SPA's RPC calls now succeed using the same
   session cookie, and `users.list` returns real rows from the database.
4. Use the **counter** (`−` / `+`): each click is a mutating `counter.adjust` RPC
   call that writes a per-user value to the database and returns the new count.
   Reload the page, it persists.
5. **Log out** posts to Phoenix's `DELETE /users/log-out`; the SPA falls back to
   the logged-out state.

## How the integration works

### Auth - reuse Phoenix's `current_scope`

Phoenix's generated `UserAuth.fetch_current_scope_for_user/2` plug reads the
session token and assigns `conn.assigns.current_scope`. The RPC route runs that
exact plug, and a one-line context builder lifts the scope into the RPC context:

```elixir
# rpc/context.ex
def build(conn),
  do: %RpcElixir.Context{assigns: %{current_scope: conn.assigns[:current_scope]}}
```

A tiny middleware authorizes against it, no session parsing, no user lookup of
its own:

```elixir
# rpc/middleware/require_user.ex
def call(%Resolution{ctx: %{assigns: %{current_scope: %{user: user}}}} = res, _opts)
    when not is_nil(user),
    do: Resolution.assign(res, :current_user, user)

def call(res, _opts),
  do: Resolution.halt(res, %RpcError{code: :unauthorized, message: "not logged in"})
```

Login/logout stay in Phoenix's controllers because RPC handlers can't write to the
response (no cookie/session mutation). `auth.me` is RPC because it only *reads* the
scope. `counter.adjust` shows the other side: handlers *can* write to the
database, only the HTTP response is off-limits, so a state-changing procedure
fits the RPC contract fine.

### CSRF - reuse Phoenix's `protect_from_forgery`

The RPC route goes through a pipeline that includes Phoenix's CSRF plug, and
`RpcElixir.Plug`'s own content-type CSRF defense is turned off, one mechanism,
not two:

```elixir
# router.ex
pipeline :rpc do
  plug :accepts, ["json"]
  plug :fetch_session
  plug :protect_from_forgery            # Phoenix's CSRF - reused
  plug :fetch_current_scope_for_user    # Phoenix's auth - reused
end

scope "/" do
  pipe_through :rpc
  forward "/rpc", RpcElixir.Plug,
    router: PhoenixExampleWeb.RpcRouter,
    path_prefix: "/rpc",
    ctx_builder: &PhoenixExampleWeb.Rpc.Context.build/1,
    require_content_type: false         # Phoenix owns CSRF
end
```

For JSON, `Plug.CSRFProtection` validates the **`x-csrf-token` header**. The SPA
reads the token from the standard `<meta name="csrf-token">` tag (exactly like
LiveView's `app.js`) and sends it on every call:

```ts
// client/src/rpc.ts
export const rpc = createRpcClient({
  baseUrl: "/rpc",
  credentials: "same-origin",
  headers: { "x-csrf-token": csrfToken },
});
```

That `<meta>` tag is why Phoenix serves the SPA's HTML shell
([`SpaController`](server/lib/phoenix_example_web/controllers/spa_controller.ex) +
[`SpaHTML`](server/lib/phoenix_example_web/controllers/spa_html.ex)) while Vite
bundles the React app, the standard Vite *backend-integration* setup. A `POST`
to `/rpc/*` without the token is rejected with `403` by Phoenix, not by the RPC
library.

### Types - identical to a plain Plug app

The `:elixir_ts_rpc` compiler (in `mix.exs` `compilers:`, configured in
`config/config.exs`) regenerates `client/src/rpc.gen.ts` from the router's
`@spec`s on every `mix compile`, which Phoenix already runs on boot and reload.
There is **no SPA-side codegen script**. Phoenix changes nothing about the type
pipeline. `DateTime` fields cross the wire as epoch-millis (`UnixMillis` alias).

## Project structure

```
examples/phoenix/
  run.sh                       boot SQLite + Phoenix (:4000) + Vite (:5173)
  server/                      stock `mix phx.new` + `mix phx.gen.auth` app, plus:
    config/config.exs            +:elixir_ts_rpc codegen config
    config/dev.exs               +:vite_dev_server
    lib/phoenix_example/accounts.ex          +list_users/0, +fetch_user/1, +adjust_user_count/2
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
    src/App.tsx                  anonymous -> login link; logged-in -> users table
    src/api/auth.ts              logout (Phoenix DELETE via form)
```

## What this example proves

- RPC authenticates against Phoenix's session-derived `current_scope` - **zero
  auth code** written for RPC.
- Phoenix's `protect_from_forgery` guards the RPC route; `RpcElixir.Plug`'s own
  CSRF defense is disabled - **one CSRF mechanism**, Phoenix's.
- Registration, login, logout, password reset, secure hashing, and DB-backed
  sessions all come from `mix phx.gen.auth` untouched.
- `@spec` → TypeScript codegen works exactly as in a plain Plug app, owned by the
  Phoenix compile step.
- The write path works too: `counter.adjust` is a mutating procedure that
  validates input, persists to the database, and returns a typed result the SPA
  renders live.

## Tests

```bash
cd server && mix test
```

`test/.../rpc_integration_test.exs` drives the real pipeline: an unauthenticated
call returns a typed `unauthorized`; an authenticated call returns real database
users, proving the RPC layer reuses Phoenix's auth.
