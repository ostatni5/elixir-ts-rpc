# React + TanStack Query example

A minimal SPA showing [`@elixir-ts-rpc/react`](../../packages/react) — the
TanStack Query adapter — driving queries and mutations through the generated
client, with typed data and typed errors.

It's intentionally client-only: it reuses the [`examples/basic`](../basic) Elixir
server (cookie-session auth, a `users` handler) rather than shipping its own.

## Run it

```bash
# 0. From the repo root: install workspaces and build the packages this client
#    imports (they resolve to dist/, which is not checked in).
npm install && npm run build -w @elixir-ts-rpc/client -w @elixir-ts-rpc/react

# 1. Generate src/rpc.gen.ts from the basic example's router (it is not checked in)
(cd examples/basic/server && mix deps.get && mix compile)
npm run rpc:gen -w @examples/react-query-client

# 2. Boot the basic example's Elixir server (listens on :4001)
cd examples/basic/server
mix run --no-halt

# 3. In another terminal, boot this client (Vite on :5174, proxying /rpc + /auth to :4001)
cd examples/react-query/client
npm run dev
```

Open http://localhost:5174 and log in with **alice / wonderland**.

## What to look at

- [`src/rpc.ts`](client/src/rpc.ts) — `createRpcReact(createRpcClient(...))`.
  Bring-your-own `<QueryClientProvider>` lives in
  [`src/main.tsx`](client/src/main.tsx).
- [`src/App.tsx`](client/src/App.tsx) — bound `rpc.auth.me.useQuery` /
  `rpc.users.list.useQuery`, a `rpc.users.update.useMutation` that invalidates the
  list via `rpc.users.list.queryKey()`, and an exhaustive `switch` over the
  mutation's typed `error.code`.

## Regenerating the client

`src/rpc.gen.ts` is generated from the basic server's router and is not checked
in. Regenerate it with:

```bash
cd examples/react-query/client
npm run rpc:gen
```
