<script setup>
import { withBase } from "vitepress";
</script>

# Examples

The repo has three runnable examples plus a browser playground. Two of the three
are full-stack. Those two differ in framework and auth.

## Basic: React/Vite SPA + Plug

Cookie-session auth, on both server and client.

The workspace packages build to `dist/`. That is not committed. Build them
once, from the repo root:

```bash
npm install
npm run build -w @elixir-ts-rpc/client
```

Then run the example:

```bash
cd examples/basic
./run.sh
# open http://localhost:5173  (alice / wonderland)
```

[Browse examples/basic →](https://github.com/ostatni5/elixir-ts-rpc/tree/main/examples/basic)

## Phoenix: typed RPC on a stock Phoenix app

It reuses the authentication from `mix phx.gen.auth`. It also reuses Phoenix's
`protect_from_forgery` CSRF. You write no auth code yourself. One CSRF
mechanism covers the whole app.

[Browse examples/phoenix →](https://github.com/ostatni5/elixir-ts-rpc/tree/main/examples/phoenix)

## React + TanStack Query

A client-only SPA for the [`@elixir-ts-rpc/react`](/guide/react) adapter. Data
and errors are typed in `useQuery` and `useMutation`. It reuses the Elixir
server from the basic example.

`src/rpc.gen.ts` is not committed either. Set up from the repo root:

```bash
npm install
npm run build -w @elixir-ts-rpc/client -w @elixir-ts-rpc/react
(cd examples/basic/server && mix deps.get)
npm run rpc:gen -w @examples/react-query-client
```

Then start both sides:

```bash
# terminal 1: backend on :4001
cd examples/basic/server && mix run --no-halt

# terminal 2: SPA on :5174
npm run dev -w @examples/react-query-client
# open http://localhost:5174  (alice / wonderland)
```

[Browse examples/react-query →](https://github.com/ostatni5/elixir-ts-rpc/tree/main/examples/react-query)

## Playground: codegen in your browser

[**Open the playground →**](https://elixir-ts-rpc-playground.netlify.app)

Edit an Elixir `@spec` on the left, watch the generated TypeScript client change
on the right. Nothing to install and no server involved. `RpcElixir.Codegen` is
the real one, compiled to WebAssembly and running in the tab.

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

That is the guided tour, the same one the **▶ Guided tour** button runs in the
app.

It is a simulation, not a project. No call reaches a server, everything has to
live in one buffer, and it pins Elixir 1.17.3. The app spells out the full list
behind its own **⚠ Simulated environment** button.

[Browse examples/playground →](https://github.com/ostatni5/elixir-ts-rpc/tree/main/examples/playground)

::: info No live backend here
The playground demonstrates codegen only. For a working round trip, clone the
repo and run one of the examples above. This static site cannot run Elixir.
:::
