# Getting started

This guide goes from an empty project to a typed browser call. You need a Mix
project with [Plug](https://hex.pm/packages/plug) in your supervision tree. Use
`plug_cowboy` or Phoenix's endpoint.

The [playground](https://elixir-ts-rpc-playground.netlify.app) runs this same
codegen in your browser, so you can see the generated output before installing
anything.

**Requirements:** Elixir `~> 1.17` on OTP 26+. Elixir 1.19+ is recommended.

| Elixir | Supported | Notes |
| --- | --- | --- |
| 1.19+ | Yes | Recommended. Everything works. |
| 1.18 | Yes | `RpcElixir.Types.FromInferred` is unavailable. |
| 1.17 | Yes | Also add `{:jason, "~> 1.4"}` to your deps. |
| 1.16 and older | No | |

Elixir's built-in `JSON` module arrived in 1.18. On 1.17 the library falls back to
[Jason](https://hex.pm/packages/jason), which you add yourself.

`FromInferred` reads the compiler's set-theoretic signatures, which only exist
from 1.19 on. It is experimental either way. The `@spec` backend
(`RpcElixir.Types.FromSpec`) is the default and works on every supported version.

## Just want to see it run?

Full-stack example: React/Vite SPA, Elixir Plug backend, cookie-session auth.

```sh
git clone https://github.com/ostatni5/elixir-ts-rpc
cd elixir-ts-rpc/examples/basic
./run.sh
# open http://localhost:5173  (alice / wonderland)
```

## 1. Add the dependency

```elixir
# mix.exs
def deps do
  [{:elixir_ts_rpc, "~> 0.0.2"}]
end
```

A path or GitHub dep also works. Use one for a monorepo or for local work:

```elixir
{:elixir_ts_rpc, path: "../rpc_elixir"}
{:elixir_ts_rpc, github: "ostatni5/elixir-ts-rpc", sparse: "apps/rpc_elixir"}
```

The Hex package and OTP app are `:elixir_ts_rpc`. Use that name in `deps`,
`config`, and `compilers:`. The module namespace is `RpcElixir.*`.

## 2. Write a handler

A handler is a plain module. Its functions take `(input, ctx)` and return
`{:ok, output} | {:error, error}`. The `@spec` is the only source of types.
Input arrives with atom keys. Match `%{id: id}`, never `%{"id" => id}`.

```elixir
defmodule MyApp.Handlers.Users do
  use RpcElixir.Handler

  @spec get(%{id: integer()}, RpcElixir.Context.t()) ::
          {:ok, %{id: integer(), name: String.t()}} | {:error, :not_found}
  def get(%{id: id}, _ctx) do
    case MyApp.Users.fetch(id) do
      {:ok, user} -> {:ok, %{id: user.id, name: user.name}}
      :error -> {:error, :not_found}
    end
  end
end
```

`use RpcElixir.Handler` is the recommended default, and `expose` in the next
step requires it. See `RpcElixir.Handler` for the BEAM-on-disk alternative.

The module is the unit you publish. Group the functions that belong to one slice
of your API into one handler, and the router stays one line per handler.

## 3. Register a router

A router publishes handlers. `expose` publishes a whole module at once:

```elixir
defmodule MyApp.RpcRouter do
  use RpcElixir.Router

  scope "users" do
    expose MyApp.Handlers.Users  # "users.get", "users.list", ...
  end
end
```

Every public, `@spec`'d, arity-2 function of the module becomes a procedure named
after the function, under the scope prefix. Add another spec'd arity-2 function
to the handler and it is published on the next compile, with no router edit.

The module must `use RpcElixir.Handler`, or `expose` raises. Helpers you keep as
`defp`, or leave without a `@spec`, stay unpublished. So the exposed module *is*
your API surface, and there is no second list of registrations to keep in sync.

`scope` groups handlers. They share a name prefix, middleware, or both:

```elixir
defmodule MyApp.RpcRouter do
  use RpcElixir.Router

  scope "users", middleware: [MyApp.RequireUser] do
    expose MyApp.Handlers.Users
  end

  scope "counter" do
    expose MyApp.Handlers.Counter  # "counter.get", "counter.adjust", ...
  end
end
```

The prefix is optional. `scope middleware: [MyApp.RequireUser] do ... end`
shares middleware without renaming. `:middleware` is the only option a scope
takes. Any other key is a compile error.

Scope middleware, and `:middleware` passed to `expose` itself, apply to every
function in the module. Splitting handlers along their middleware is the usual
shape: one module per auth level.

### Naming procedures one at a time

`procedure` is the manual alternative. It takes a wire name and a remote arity-2
capture, and checks the `@spec` at compile time the same way:

```elixir
scope "users" do
  procedure "get", &MyApp.Handlers.Users.get/2    # "users.get"
  procedure "list", &MyApp.Handlers.Users.list/2  # "users.list"
end
```

Reach for it when the wire name must differ from the function name, when only
part of a module should be reachable, when one function needs its own
middleware, or when you want the published surface auditable line by line. The
two mix freely in one router, as long as no two procedures claim the same name.
See `RpcElixir.Router`.

Import the formatter config. It keeps `procedure "x", &…` free of parentheses:

```elixir
# .formatter.exs
[import_deps: [:elixir_ts_rpc]]
```

## 4. Mount the plug

```elixir
defmodule MyApp.Endpoint do
  use Plug.Builder

  plug RpcElixir.Plug, router: MyApp.RpcRouter
end
```

`POST /rpc/users.get` now dispatches `"users.get"`. `:path_prefix` defaults to
`"/rpc"`. The plug takes five more options. Several are security-relevant. See
[Plug options](plug-options.md).

## 5. Wire up codegen

Point codegen at your router and an out path. Then add the compiler.

```elixir
# config/config.exs
config :elixir_ts_rpc,
  router: MyApp.RpcRouter,
  out: Path.expand("../assets/src/rpc.gen.ts", __DIR__)
```

```elixir
# mix.exs
def project do
  [
    # ...
    compilers: Mix.compilers() ++ [:elixir_ts_rpc]
  ]
end
```

Gitignore the generated file. It is a build artifact, and it carries an absolute
path per procedure, the link from each method back to its handler line. See
[Codegen workflows](https://ostatni5.github.io/elixir-ts-rpc/guide/codegen-workflow).

The compiler hook regenerates on every `mix compile`. That is the default for
day-to-day work. `mix rpc.gen.ts.watch` regenerates on save. `mix rpc.gen.ts`
runs once, which suits CI. See
[Codegen workflows](https://ostatni5.github.io/elixir-ts-rpc/guide/codegen-workflow).

## 6. Call it from TypeScript

Install the runtime client:

```sh
npm install @elixir-ts-rpc/client
```

```ts
import { createRpcClient } from "./rpc.gen";

const client = createRpcClient({ baseUrl: "/rpc" });

// Typed: input { id: number }, output { id: number; name: string },
// and a catchable typed error (UsersGetError = DomainError<"not_found">).
const user = await client.users.get({ id: 1 });
```

Hover `client.users.get` in your editor. Its JSDoc carries the handler MFA and a
link to the line the types came from. Follow it to land on the Elixir function.

## Where to go next

- [Using the client](https://ostatni5.github.io/elixir-ts-rpc/guide/client) for
  typed errors, abort signals, interceptors, and cross-origin auth.
- [React + TanStack Query](https://ostatni5.github.io/elixir-ts-rpc/guide/react)
  for bound `useQuery`/`useMutation` hooks.
- [Writing middleware](middleware.md)
  for auth, assigns, cookies, and session writes.
- [Plug options](plug-options.md) for
  body limits, origins, and content-type checks.
- [Supported types](supported-types.md) for the `@spec` to TypeScript mapping.
- [Handling errors](errors.md) for error shapes, wire format, and status codes.
- [Custom types](custom-types.md) for branded wires and `wire_aliases`.

## What works today

- **Types recovered from your functions.** `RpcElixir.Types.FromSpec` reads
  input, output, and error types from `@spec` in BEAM debug info. No macro is
  needed. (`RpcElixir.Types.FromInferred` is an experimental set-theoretic
  backend for when the compiler can tell us directly.)
- **Whole-module registration.** `expose` publishes every spec'd arity-2
  function of a handler module, so the router lists handlers rather than
  functions. `procedure` names them one at a time when you want that instead.
  `scope` shares a prefix and middleware over either.
- **HTTP (Plug) transport.** `RpcElixir.Plug`, `Router`, and `Dispatcher` run
  the request pipeline: lookup, middleware, input validation, the handler,
  output validation, and serialization. Middleware gets a request-scoped
  `Context` and `Resolution`.
- **Typed errors end to end.** Codegen emits `DomainError<Code, Details>`
  aliases. The client throws them as a catchable `RpcError`.
- **TypeScript codegen** via `mix rpc.gen.ts`, the `:elixir_ts_rpc` compiler, and
  a file watcher.
- **Source links back to Elixir.** Every generated method gets a JSDoc link to
  the handler line that produced it, clickable from your editor.
- **Custom and branded wire types**: `CustomType` with `ts_type/0`, branded
  string and number wires, `RpcElixir.UnixMillis`, and `wire_aliases`.
- **TypeScript client** `@elixir-ts-rpc/client`: abort signals, header and
  credential handling, typed `RpcError` narrowing, an awaited interceptor chain,
  and a central `onError` hook.
- **React adapter** `@elixir-ts-rpc/react`, typed hooks over the generated client.

## Not built yet

- **Realtime.** There is no SSE, Phoenix Channels, or WebSocket transport. HTTP
  is request/response only.
- **Built-in client middleware** for retry, auth refresh, batching, or dedup.
- **More framework adapters.** Only React ships today.

Handlers cannot write to the HTTP response. So auth login and logout live
outside RPC, as plain Plug routes. Middleware is not limited that way. It can
set cookies, headers, and session values. It uses `RpcElixir.Resolution`. See
[Writing middleware](middleware.md)
and [How it works](https://ostatni5.github.io/elixir-ts-rpc/guide/how-it-works).
