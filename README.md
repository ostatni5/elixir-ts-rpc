# elixir-ts-rpc

Typed RPC between Elixir servers and TypeScript clients. Define procedures in
Elixir with ordinary `@spec` typespecs and a small router DSL. The fully typed
TypeScript client is generated from them, with no separate schema language and
no hand-written TypeScript.

📖 **[Documentation & guide → ostatni5.github.io/elixir-ts-rpc](https://ostatni5.github.io/elixir-ts-rpc/)**

> **Status:** early release `0.0.1`, pre-1.0. APIs may change before 1.0. The
> HTTP Plug transport and TypeScript codegen are working and tested end-to-end
> in [examples/basic](examples/basic). Realtime transports and framework
> adapters are not built yet. See
> [what works and what's planned](https://ostatni5.github.io/elixir-ts-rpc/guide/getting-started).

**Requirements:** Elixir `~> 1.19`, OTP 26+. Handlers cannot write to the HTTP
response, so they cannot set cookies, headers, or session state, and auth
login/logout must live outside RPC, as plain Plug routes. See
[examples/basic](examples/basic).

## In one glance

You write a handler with a classic `@spec`:

```elixir
@spec get_user(%{id: integer()}, RpcElixir.Context.t()) ::
        {:ok, %{id: integer(), name: String.t()}} | {:error, :not_found}
def get_user(%{id: id}, _ctx), do: ...
```

`mix rpc.gen.ts` reads the spec from BEAM debug info and emits a typed client.
The browser calls `client.users.get({ id })` with full inference and typed
errors. See [how it works](https://ostatni5.github.io/elixir-ts-rpc/guide/how-it-works)
for the full pipeline.

## Quick start

**Just want to see it run?** Boot the full-stack example:

```bash
cd examples/basic
./run.sh
# open http://localhost:5173 (alice / wonderland)
```

**Adding it to your own app?** Follow the end-to-end
[Getting started in your own app](apps/rpc_elixir/README.md#getting-started-in-your-own-app)
guide: add the dep, write a handler, register a router, mount the plug, wire up
codegen, and make a typed call from TypeScript.

## Layout

- [`apps/rpc_elixir`](apps/rpc_elixir/README.md): the Elixir library covering
  codegen, router, plug, types, and custom types.
- [`packages/client`](packages/client/README.md): the `@elixir-ts-rpc/client`
  TypeScript runtime.
- [`examples/basic`](examples/basic): full-stack React + Elixir Plug demo.
- [`examples/phoenix`](examples/phoenix): the same on Phoenix, reusing
  `phx.gen.auth` + Phoenix CSRF.
- [`docs`](docs): the VitePress documentation site.

## Documentation

The full guide covering how it works, codegen workflows, supported types, and
the examples lives at
**[ostatni5.github.io/elixir-ts-rpc](https://ostatni5.github.io/elixir-ts-rpc/)**.

## License

MIT. See [LICENSE](LICENSE).
