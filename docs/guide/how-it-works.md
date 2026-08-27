# How it works

One Elixir `@spec` drives both sides. It validates at runtime. It also
generates the TypeScript.

```text
Elixir handler (@spec)  ──►  Router + Dispatcher (Plug)  ──►  HTTP /rpc/*
        │                                                         ▲
        └──►  Type resolution (FromSpec)  ──►  TS codegen  ──►  typed client
```

## 1. Write a handler with a `@spec`

A procedure is a module function with a typespec. It takes two arguments.
First the decoded input. Then a request-scoped `RpcElixir.Context`.

```elixir
@spec get(%{id: String.t()}, RpcElixir.Context.t()) ::
        {:ok, %{id: String.t(), email: String.t()}} | {:error, :not_found}
def get(%{id: id}, _ctx), do: ...
```

`:ok` carries the success payload. Each `:error` branch becomes a typed client
code.

## 2. Expose the module on a router

The handler module is the unit you publish. `expose` registers every public,
spec'd, arity-2 function in it, each named after the function:

```elixir
defmodule MyApp.RpcRouter do
  use RpcElixir.Router

  scope "users" do
    expose MyApp.Handlers.Users   # → "users.get", "users.list", ...
  end
end
```

So the router is a list of handlers, not a list of functions. Add a spec'd
arity-2 function to the module and it is served on the next compile. Helpers you
keep as `defp`, or leave unspec'd, are not reachable.

`procedure` is the manual alternative, one wire name and one capture at a time.
Use it when the wire name must differ from the function name, when only part of a
module should be reachable, or when one function needs its own middleware. Both
forms are validated at compile time and both nest in `scope`. See
[Getting started](/guide/getting-started#_3-register-a-router).

## 3. Resolve types from BEAM debug info

`RpcElixir.Types.FromSpec` reads your specs from compiled BEAM debug info. You
write no compile-time macro. You keep no schema in sync. (`FromInferred` is an
experimental set-theoretic backend.)

## 4. Generate the TypeScript client

`mix rpc.gen.ts` writes the typed client. There are three ways to run it:
compiler hook, watcher, explicit task. See
[Codegen workflows](/guide/codegen-workflow).

Each method also keeps a link to the handler it came from, read from the same
debug info as the types:

```ts
/** [users.ex:78](file://…/lib/my_app/handlers/users.ex#L78) — `MyApp.Handlers.Users.get/2` */
get: RpcMethod<UsersGetInput, UsersGetOutput, UsersGetError>;
```

Hover `client.users.get` in your editor and that link is in the tooltip.
Following it opens the Elixir function. So the generated file is not a dead end
you read and then go hunting through `lib/` from.

::: tip See it happen
The [playground](https://elixir-ts-rpc-playground.netlify.app) runs this same
generator in your browser. Edit a `@spec` on the left, watch the client change
on the right.
:::

## 5. Serve requests through the Plug pipeline

`RpcElixir.Plug`, `Router`, and `Dispatcher` run each request. See
[Plug options](/guide/plug-options) for what the plug accepts. The steps are
lookup, middleware, input validation, handler, output validation, serialize.
They pass a request-scoped `Context` and `Resolution` along. That is what makes
middleware possible. The chain runs before input validation. So auth middleware
can reject a call even when the input is invalid. See
[Writing middleware](/guide/middleware) to write your own.

::: tip Handlers can't touch the HTTP response
Handlers cannot write cookies or headers. They cannot change the session
either. Procedures stay pure and transport-agnostic. Middleware can do all
three, through `RpcElixir.Resolution`. So auth login and logout live outside
RPC. Write them as plain Plug routes, or as middleware. See the
[examples](/guide/examples).
:::

## 6. Call it from the browser, fully typed

```ts twoslash
import { createRpcClient } from "./rpc.gen";

const client = createRpcClient({ baseUrl: "/rpc" });

const user = await client.users.get({ id: "u_1" });
const email = user.email;
//    ^?
```

Errors arrive as an `RpcError` you can catch. Each procedure types it as
`DomainError<Code, Details>`:

```ts twoslash
import { createRpcClient } from "./rpc.gen";
const client = createRpcClient({ baseUrl: "/rpc" });
// ---cut---
import { RpcError } from "@elixir-ts-rpc/client";

try {
  await client.users.get({ id: "u_999" });
} catch (err) {
  if (err instanceof RpcError && err.code === "not_found") {
    // handle the typed :not_found branch
  }
}
```

See [Using the client](/guide/client) for more. It covers client options,
error-narrowing guards, abort signals, `onError`, and interceptors.
