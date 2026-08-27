# elixir_ts_rpc

Typed RPC between Elixir and TypeScript. **One `@spec` is the whole contract.**
It validates requests at runtime *and* generates your TypeScript client. There is
no second schema to keep in sync.

🧪 **[Playground → edit a `@spec`, watch the client regenerate](https://elixir-ts-rpc-playground.netlify.app)**
runs this codegen in your browser. Nothing to install.

## How it looks

Write a handler with a normal `@spec`:

```elixir
defmodule MyApp.Handlers.Users do
  use RpcElixir.Handler

  @spec get(%{id: integer()}, RpcElixir.Context.t()) ::
          {:ok, %{id: integer(), name: String.t()}} | {:error, :not_found}
  def get(%{id: id}, _ctx), do: MyApp.Users.fetch(id)
end
```

Expose the module on a router:

```elixir
defmodule MyApp.RpcRouter do
  use RpcElixir.Router

  scope "users" do
    expose MyApp.Handlers.Users   # "users.get", "users.list", ...
  end
end
```

Every public, `@spec`'d, arity-2 function of the module is published, named after
the function. Add another one to the handler and it appears on the next compile.
When you need a different wire name, a subset of a module, or per-function
middleware, name procedures one at a time with `procedure` instead. See
`RpcElixir.Router`.

`mix rpc.gen.ts` reads that spec from BEAM debug info. It then writes a typed client:

```ts
const user = await client.users.get({ id: 1 });
//    ^? { id: number; name: string }
```

## Why

- **No schema DSL.** No GraphQL SDL, no OpenAPI document, no Zod mirror, no
  macro. The `@spec` you would write anyway *is* the schema.
- **A module is an API surface.** `expose` publishes a whole handler module, so
  the router does not grow a line per function. Explicit `procedure` calls are
  there when you want the surface pinned down by hand.
- **The spec is enforced.** The dispatcher validates input and output against it
  on every request. The TypeScript types are not a hopeful annotation.
- **Errors are typed too.** Every `{:error, reason}` branch becomes a
  `DomainError` the client catches and narrows.
- **The client points back at your code.** Every generated method carries a link
  to the handler line that produced it. Hover a call in TypeScript, follow the
  link, land on the Elixir function.
- **Fits your Phoenix app.** Mount one plug in your existing endpoint. Keep
  `mix phx.gen.auth` and CSRF exactly as they are.

Weighing it against Absinthe, OpenAPI codegen, LiveView, or hand-written
endpoints? See
[Comparison](https://ostatni5.github.io/elixir-ts-rpc/guide/comparison).

## Scope

Pre-1.0 (`0.0.2`), so APIs may change. You need Elixir `~> 1.17` on OTP 26+.
Elixir 1.19+ is recommended. On 1.17 add `{:jason, "~> 1.4"}` to your deps, since
Elixir's built-in `JSON` module only arrived in 1.18.
Transport is HTTP request/response only. There is no SSE, Channels, or WebSocket
transport yet, and React is the only framework adapter. Full list:
[what works today](getting-started.md#what-works-today).

## Install

```elixir
# mix.exs
def deps do
  [{:elixir_ts_rpc, "~> 0.0.2"}]
end
```

The Hex package and OTP app are `:elixir_ts_rpc`. The module namespace is
`RpcElixir.*`.

Next: **[Getting started](getting-started.md)**.

## Documentation

The server side lives here on HexDocs:

- **[Getting started](getting-started.md)**
- **[Plug options](plug-options.md)**: everything `RpcElixir.Plug` accepts
- **[Writing middleware](middleware.md)**: the `RpcElixir.Middleware` behaviour
- **[Supported types](supported-types.md)**: how `@spec` maps to TypeScript
- **[Handling errors](errors.md)**: error shapes, wire format, status codes
- **[Custom types](custom-types.md)**: branded wires, `RpcElixir.UnixMillis`, `wire_aliases`
- Module reference: `RpcElixir.Router`, `RpcElixir.Plug`, `RpcElixir.Handler`,
  `RpcElixir.Middleware`, `RpcElixir.CustomType`.

The client side lives on the [guide site](https://ostatni5.github.io/elixir-ts-rpc/):

- **[How it works](https://ostatni5.github.io/elixir-ts-rpc/guide/how-it-works)**: the request lifecycle
- **[Comparison](https://ostatni5.github.io/elixir-ts-rpc/guide/comparison)**: versus Absinthe, OpenAPI, LiveView, gRPC
- **[Using the client](https://ostatni5.github.io/elixir-ts-rpc/guide/client)**: `@elixir-ts-rpc/client`
- **[React + TanStack Query](https://ostatni5.github.io/elixir-ts-rpc/guide/react)**: `@elixir-ts-rpc/react` hooks
- **[Codegen workflows](https://ostatni5.github.io/elixir-ts-rpc/guide/codegen-workflow)**: compiler hook, watcher, CI task
- **[Playground](https://elixir-ts-rpc-playground.netlify.app)**: edit a `@spec` in the browser and watch the client regenerate, with the real codegen compiled to WebAssembly
- **[Examples](https://ostatni5.github.io/elixir-ts-rpc/guide/examples)**: runnable Plug and Phoenix apps

## License

[MIT](https://github.com/ostatni5/elixir-ts-rpc/blob/main/apps/rpc_elixir/LICENSE).
