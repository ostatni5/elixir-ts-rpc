---
layout: home

hero:
  name: elixir-ts-rpc
  text: Typed RPC, Elixir ↔ TypeScript
  tagline: >-
    Your Elixir functions callable from TypeScript. The function is the contract.
  actions:
    - theme: brand
      text: Get started
      link: /guide/getting-started
    - theme: alt
      text: Try the playground
      link: https://elixir-ts-rpc-playground.netlify.app

features:
  - icon: 🧬
    title: No schema, anywhere
    details: No GraphQL SDL, no OpenAPI document, no Zod mirror. There is a function, and the compiler already knows its shape.
  - icon: 🛟
    title: Typed errors end-to-end
    details: Elixir error unions become typed, catchable errors in TypeScript.
  - icon: 🔗
    title: Click through to the handler
    details: Every generated method links to the Elixir line that produced it. Hover the call, follow the link, land on the handler.
  - icon: 🔥
    title: Fits your Phoenix app
    details: Mount one plug in your existing endpoint. Keep mix phx.gen.auth, CSRF, and your session exactly as they are.
  - icon: ⚙️
    title: Codegen that fits your loop
    details: Regenerate on every compile, on file change, or on demand in CI.
  - icon: 🧪
    title: Real, full-stack examples
    details: A React SPA on Plug. The same on a stock Phoenix app, with auth and CSRF.
---

<script setup>
import { withBase } from "vitepress";
</script>

<div style="max-width: 1152px; margin: 4rem auto 0; padding: 0 24px;">

## See it run

<div>
<video
  controls
  playsinline
  preload="none"
  width="1440"
  height="760"
  :poster="withBase('/playground-tour.jpg')"
  :src="withBase('/playground-tour.mp4')"
  style="display: block; width: 100%; height: auto; border-radius: 8px; border: 1px solid var(--vp-c-divider);"
></video>
</div>

</div>

<div style="max-width: 960px; margin: 1.25rem auto 0; padding: 0 24px;">

A guided tour of the [playground](https://elixir-ts-rpc-playground.netlify.app).
Edit a `@spec`, watch the client regenerate, follow a method back to the handler
that produced it, then rename a field and watch the TypeScript break. That is
the real codegen running in the browser, compiled to WebAssembly.
[Try it yourself →](https://elixir-ts-rpc-playground.netlify.app)

## How it looks

A procedure is an ordinary function. Its `@spec` is how you tell the compiler
its shape today:

```elixir
defmodule MyApp.Users do
  use RpcElixir.Handler

  @spec get(%{id: String.t()}, RpcElixir.Context.t()) ::
          {:ok, %{id: String.t(), email: String.t()}} | {:error, :not_found}
  def get(%{id: id}, _ctx), do: ...
end
```

Expose the module on a router:

```elixir
scope "users" do
  expose MyApp.Users   # → "users.get", "users.list", …
end
```

Run `mix rpc.gen.ts`, then call it from the browser:

```ts twoslash
import { createRpcClient } from "./rpc.gen";
const client = createRpcClient({ baseUrl: "/rpc" });
// ---cut---
const user = await client.users.get({ id: "u_1" });
const email = user.email;
//    ^?
```

[Get started →](/guide/getting-started)

</div>
