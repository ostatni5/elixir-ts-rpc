---
layout: home

hero:
  name: elixir-ts-rpc
  text: Typed RPC, Elixir ↔ TypeScript
  tagline: >-
    Define procedures in Elixir with ordinary @spec typespecs and a small router
    DSL. The fully typed TypeScript client is generated from them. No separate
    schema language, no hand-written TypeScript.
  actions:
    - theme: brand
      text: Get started
      link: /guide/getting-started
    - theme: alt
      text: How it works
      link: /guide/how-it-works
    - theme: alt
      text: View on GitHub
      link: https://github.com/ostatni5/elixir-ts-rpc

features:
  - icon: 🧬
    title: Types from your typespecs
    details: Input, output, and error types are read straight from your Elixir typespecs. No separate schema language, no TypeScript types to keep in sync.
  - icon: 🔌
    title: HTTP transport included
    details: A Plug pipeline validates input, runs your handler, validates output, and serializes, all with request-scoped middleware.
  - icon: 🛟
    title: Typed errors end-to-end
    details: Your Elixir error unions become typed, catchable errors in TypeScript. The failure path stays as typed as the happy path.
  - icon: ⚙️
    title: Codegen that fits your loop
    details: Regenerate the client on every compile, on file change, or on demand in CI. The client never drifts from your types.
  - icon: 🏷️
    title: Custom & branded wire types
    details: Control how values cross the wire. Send branded strings and numbers, epoch-millis datetimes, and your own custom types.
  - icon: 🧪
    title: Real, full-stack examples
    details: A React SPA on a Plug backend, and the same typed RPC on a stock Phoenix app reusing its auth and CSRF.
---

<div style="max-width: 960px; margin: 4rem auto 0; padding: 0 24px;">

> **Status: early release (`0.0.1`), pre-1.0.** APIs may change before 1.0. The
> HTTP Plug transport and TypeScript codegen are working and tested end-to-end.
> Realtime transports and framework adapters are not built yet.

## In one glance

Write a handler with a classic `@spec`:

```elixir
@spec get_user(%{id: integer()}, RpcElixir.Context.t()) ::
        {:ok, %{id: integer(), name: String.t()}} | {:error, :not_found}
def get_user(%{id: id}, _ctx), do: ...
```

Run `mix rpc.gen.ts`, and call it from the browser with full inference and typed
errors:

```ts
const user = await client.users.get({ id: 1 });
//    ^? { id: number; name: string }
```

That's the whole idea. Your Elixir typespecs *are* the contract.

</div>
