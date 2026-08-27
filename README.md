# elixir-ts-rpc

Typed RPC between Elixir and TypeScript. **Your Elixir function is the contract.**
The compiler already knows its shape, so it validates requests at runtime *and*
generates your TypeScript client. There is no schema.

📖 **[Documentation & guide → ostatni5.github.io/elixir-ts-rpc](https://ostatni5.github.io/elixir-ts-rpc/)**

🧪 **[Playground → edit a @spec, watch the client regenerate](https://elixir-ts-rpc-playground.netlify.app)** (runs the real codegen in your browser)

## How it looks

```elixir
@spec get(%{id: integer()}, RpcElixir.Context.t()) ::
        {:ok, %{id: integer(), name: String.t()}} | {:error, :not_found}
def get(%{id: id}, _ctx), do: ...
```

Expose the module that holds it, and every spec'd function in it is published:

```elixir
scope "users" do
  expose MyApp.Handlers.Users   # → "users.get", "users.list", ...
end
```

`mix rpc.gen.ts` reads those specs from BEAM debug info. It then writes a typed client:

```ts
const user = await client.users.get({ id: 1 });
//    ^? { id: number; name: string }
```

## Why

- **No schema at all.** No GraphQL SDL, no OpenAPI document, no Zod mirror, no
  macro. A procedure is an ordinary Elixir function, and the types are read from
  the source it already carries.
- **A module is an API surface.** `expose` publishes a whole handler module, so
  the router does not grow a line per function. Name procedures one at a time
  with `procedure` when you want the surface pinned down by hand.
- **The contract is enforced.** The dispatcher validates input and output against
  it on every request. The TypeScript types are not a hopeful annotation.
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

## Try it

```bash
cd examples/basic
./run.sh
# open http://localhost:5173  (alice / wonderland)
```

For your own app, read **[Getting started](https://ostatni5.github.io/elixir-ts-rpc/guide/getting-started)**.

## Scope

Pre-1.0 (`0.0.2`), so APIs may change. You need Elixir `~> 1.17` on OTP 26+.
Elixir 1.19+ is recommended. On 1.17 add `{:jason, "~> 1.4"}` to your deps, since
Elixir's built-in `JSON` module only arrived in 1.18.
Transport is HTTP request/response only. There is no SSE, Channels, or WebSocket
transport yet, and React is the only framework adapter. Full list:
[what works today](https://ostatni5.github.io/elixir-ts-rpc/guide/getting-started#what-works-today).

## Layout

| Path | What |
| --- | --- |
| [`apps/rpc_elixir`](apps/rpc_elixir/README.md) | the Elixir library: codegen, router, plug, types ([HexDocs](https://hexdocs.pm/elixir_ts_rpc)) |
| [`packages/client`](packages/client/README.md) | `@elixir-ts-rpc/client`, the TypeScript runtime |
| [`packages/react`](packages/react/README.md) | `@elixir-ts-rpc/react`, the TanStack Query adapter |
| [`examples/basic`](examples/basic) | full-stack React + Elixir Plug demo |
| [`examples/phoenix`](examples/phoenix) | the same on Phoenix, reusing `phx.gen.auth` + CSRF |
| [`examples/react-query`](examples/react-query) | React adapter demo on the basic server |
| [`docs`](docs) | the VitePress guide site |

## License

[MIT](LICENSE).
