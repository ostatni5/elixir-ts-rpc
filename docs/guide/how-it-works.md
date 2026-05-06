# How it works

The contract between server and client is your Elixir `@spec`. Nothing else
declares the shape of a procedure. The typespec is the single source of truth,
and both the runtime validation and the generated TypeScript flow from it.

```text
Elixir handler (@spec)  ──►  Router + Dispatcher (Plug)  ──►  HTTP /rpc/*
        │                                                         ▲
        └──►  Type resolution (FromSpec)  ──►  TS codegen  ──►  typed client
```

## 1. Write a handler with a `@spec`

A procedure is just a module function with a classic typespec. The first
argument is the decoded input. The second is the request-scoped
`RpcElixir.Context`:

```elixir
@spec get_user(%{id: integer()}, RpcElixir.Context.t()) ::
        {:ok, %{id: integer(), name: String.t()}} | {:error, :not_found}
def get_user(%{id: id}, _ctx), do: ...
```

The return type is an `{:ok, _} | {:error, _}` union. The `:ok` branch is the
success payload. Each `:error` branch becomes a typed error code on the client.

## 2. Resolve types from BEAM debug info

`RpcElixir.Types.FromSpec` reads the spec back out of the compiled module's BEAM
debug info. There's no compile-time macro and no separate schema to keep in
sync. `FromInferred` is an experimental set-theoretic backend.

## 3. Generate the TypeScript client

`mix rpc.gen.ts` walks the resolved types and emits a typed client. See
[Codegen workflows](/guide/codegen-workflow) for the three ways to run it and
when to use each: compiler hook, watcher, and explicit task.

## 4. Serve requests through the Plug pipeline

`RpcElixir.Plug` + `Router` + `Dispatcher` run the full request lifecycle:
**lookup → input validation → handler → output validation → serialize**.
Request-scoped `Context`/`Resolution` threading gives you middleware, such as
auth that rejects a request before the handler runs.

::: tip Handlers can't touch the HTTP response
By design, handlers cannot write cookies, headers, or mutate the session. That
keeps procedures pure and transport-agnostic. But it means auth login/logout
must live outside RPC as plain Plug routes. The [examples](/guide/examples) show
the pattern.
:::

## 5. Call it from the browser, fully typed

```ts
import { createClient } from "@elixir-ts-rpc/client";

const client = createClient({ url: "/rpc" });

const user = await client.users.get({ id: 1 });
//    ^? { id: number; name: string }
```

Errors come back as a catchable `RpcError<Code, Details>`, so the failure path is
as typed as the success path:

```ts
import { RpcError } from "@elixir-ts-rpc/client";

try {
  await client.users.get({ id: 999 });
} catch (err) {
  if (err instanceof RpcError && err.code === "not_found") {
    // handle the typed :not_found branch
  }
}
```

See [Using the client](/guide/client) for the full TypeScript API. It covers
client options, the error-narrowing guards, abort signals, a central `onError`
hook, and interceptors for logging and auth refresh.
