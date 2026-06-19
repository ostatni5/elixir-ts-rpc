# Getting started

`elixir-ts-rpc` lets you define RPC procedures in Elixir using ordinary `@spec`
typespecs and a small router DSL, then generates a fully typed TypeScript client
from them. No separate schema language, no hand-written TypeScript.

::: warning Early release (`0.0.1`), pre-1.0
APIs may change before 1.0. The HTTP (Plug) transport and TypeScript codegen are
working and tested end-to-end. Realtime transports and framework adapters are
not built yet. See [Not built yet](#not-built-yet) below.
:::

## Requirements

- **Elixir `~> 1.19` on OTP 26+.**
- Handlers cannot write to the HTTP response. They cannot set cookies, headers,
  or mutate the session, so auth login/logout must live outside RPC as plain
  Plug routes. Both [examples](/guide/examples) show how.

## Just want to see it run?

Boot the full-stack basic example. It is a React/Vite SPA on an Elixir Plug
backend with cookie-session auth, wired end to end:

```bash
git clone https://github.com/ostatni5/elixir-ts-rpc
cd elixir-ts-rpc/examples/basic
./run.sh
# open http://localhost:5173  (alice / wonderland)
```

## Adding it to your own app

The end-to-end path is:

1. **Add the dep** to your Elixir app.
2. **Write a handler**, a module function with an ordinary `@spec`.
3. **Register a router** that maps procedure names to handlers.
4. **Mount the plug** so requests reach the dispatcher.
5. **Wire up codegen** so the TypeScript client regenerates from your specs.
6. **Make a typed call** from TypeScript via `@elixir-ts-rpc/client`.

The canonical, always-current walkthrough lives in the library README:
[Getting started in your own app →](https://github.com/ostatni5/elixir-ts-rpc/blob/main/apps/rpc_elixir/README.md#getting-started-in-your-own-app)

Once the basics work, see [Using the client](/guide/client) for the full
TypeScript API, which covers typed errors, abort, interceptors, and auth
refresh. See [Codegen workflows](/guide/codegen-workflow) to pick how the client
stays in sync, and [Supported types](/guide/supported-types) for the full
`@spec` → TypeScript mapping.

## What works today

- **`@spec`-driven types**: `RpcElixir.Types.FromSpec` resolves procedure
  input/output/error types from BEAM debug info. No compile-time macro required.
  `FromInferred` is an experimental set-theoretic backend.
- **HTTP (Plug) transport**: `RpcElixir.Plug` + `Router` + `Dispatcher` run the
  full lookup → input validation → handler → output validation → serialize
  pipeline.
- **Middleware framework**: request-scoped `Context`/`Resolution` threading.
- **Typed errors end-to-end**: Elixir error unions become
  `RpcError<Code, Details>` in TypeScript, thrown as a catchable `RpcError`.
- **TypeScript codegen**: `mix rpc.gen.ts`, an `:elixir_ts_rpc` compiler task,
  and a file `Watcher`.
- **Custom + branded wire types**: `CustomType` with `ts_type/0`, branded
  string/number wires, `RpcElixir.UnixMillis`, and the `wire_aliases` option.
- **TypeScript client**: `@elixir-ts-rpc/client`: `createClient`, abort-signal
  composition, header/credential handling, typed `RpcError` narrowing, an awaited
  `interceptors` chain, and a central `onError` hook.

## Not built yet

- **Realtime**: no SSE subscriptions, Phoenix Channels, or WebSocket transport.
  HTTP is request/response only.
- **Built-in client middleware**: retry, auth refresh, batching, dedup.
- **Framework adapters**: React and Svelte adapters with TanStack Query helpers.
