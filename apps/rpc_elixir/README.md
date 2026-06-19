# rpc_elixir

Typed RPC procedures for Elixir servers with TypeScript-compatible type resolution from `@spec`.

Part of [elixir-ts-rpc](https://github.com/ostatni5/elixir-ts-rpc), a typed RPC layer between Elixir servers and TypeScript clients.

📖 **[Full guide & documentation → ostatni5.github.io/elixir-ts-rpc](https://ostatni5.github.io/elixir-ts-rpc/)**

> **Status**: early release (`0.0.1`), pre-1.0. APIs may change between minor
> versions. The full HTTP/Plug RPC stack is implemented and tested - `Context`,
> `Resolution`, `Types`, `CustomType`, `Types.FromSpec`, plus `Handler`,
> `Router`, `Middleware`, `Dispatcher`, and `Plug` - along with TypeScript
> codegen (`mix rpc.gen.ts`). Realtime transports (SSE, Phoenix Channels) are not
> built yet. See the [CHANGELOG](CHANGELOG.md) for what's in each release.

**Requirements:** Elixir `~> 1.19` (OTP 26+).

## Getting started in your own app

End-to-end: from an empty handler to a typed call in the browser. Assumes a Mix
project with [Plug](https://hex.pm/packages/plug) already in your supervision
tree (e.g. via `plug_cowboy` or Phoenix's endpoint).

### 1. Add the dependency

Add it as a Hex dep:

```elixir
# mix.exs
def deps do
  [
    {:elixir_ts_rpc, "~> 0.0.1"}
  ]
end
```

For monorepo/local work, use a path or GitHub dep instead. See
[Installation](#installation) below.

### 2. Write a handler with a `@spec`

A handler is a plain module whose functions take `(input, ctx)` and return
`{:ok, output} | {:error, error}`. Write a classic `@spec`. That is the only
type source. `use RpcElixir.Handler` is the recommended default: it lets the
handler and router live in the same Mix project (see
[Handler compilation](#handler-compilation)).

`input` always arrives with **atom keys**. Pattern-match on `%{id: id}`, never
`%{"id" => id}`.

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

### 3. Register it in a router

```elixir
defmodule MyApp.RpcRouter do
  use RpcElixir.Router

  procedure "users.get", &MyApp.Handlers.Users.get/2
end
```

Each `procedure` takes a wire name and a **remote** function capture of arity 2.
The router validates the `@spec` at compile time. The DSL also has `scope`
(shares a name prefix and/or middleware across a group) and `expose` (registers
every `@spec`'d arity-2 function of a handler module). See `RpcElixir.Router`.

The DSL reads best without parens (`procedure "users.get", &…`). So that
`mix format` keeps it that way instead of rewriting to `procedure(…)`, import
this library's formatter config in your `.formatter.exs`:

```elixir
# .formatter.exs
[
  import_deps: [:elixir_ts_rpc]
]
```

(`mix format` won't strip parens that are already there, so format once after
adding this.)

### 4. Mount the plug in your endpoint

```elixir
defmodule MyApp.Endpoint do
  use Plug.Builder

  plug RpcElixir.Plug, router: MyApp.RpcRouter
end
```

A request to `POST /rpc/users.get` now dispatches the `"users.get"` procedure.
(`:path_prefix` defaults to `"/rpc"`.)

### 5. Configure codegen

Point the codegen at your router and an output path, then add the compiler so
the client regenerates on every `mix compile`:

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

See [Choosing a codegen workflow](https://github.com/ostatni5/elixir-ts-rpc#choosing-a-codegen-workflow)
for when to use the compiler hook vs. the `mix rpc.gen.ts.watch` task vs. the
one-off `mix rpc.gen.ts` task instead.

### 6. Make a typed call from TypeScript

Install the runtime client (`npm install @elixir-ts-rpc/client`) and import the
generated factory:

```ts
import { createRpcClient } from "./rpc.gen";

const client = createRpcClient({ baseUrl: "/rpc" });

// Fully typed: input { id: number }, output { id: number; name: string },
// and a catchable RpcError<"not_found"> on the error path.
const user = await client.users.get({ id: 1 });
```

See [`@elixir-ts-rpc/client`](https://github.com/ostatni5/elixir-ts-rpc/blob/main/packages/client/README.md) for catching typed
errors, abort signals, and cross-origin auth.

## Installation

The package is on Hex. See [Add the dependency](#1-add-the-dependency) above.
For monorepo/local development, use a path or GitHub dep instead:

```elixir
# same umbrella / monorepo
def deps do
  [
    {:elixir_ts_rpc, path: "../rpc_elixir"}
  ]
end
```

```elixir
# from GitHub
def deps do
  [
    {:elixir_ts_rpc, github: "ostatni5/elixir-ts-rpc", sparse: "apps/rpc_elixir"}
  ]
end
```

> **Name notes:** the Hex package / OTP application name is `:elixir_ts_rpc` (use
> it in `deps`, in `config :elixir_ts_rpc, ...`, and in `compilers:`). The Elixir
> module namespace is `RpcElixir.*` (`RpcElixir.Router`, `RpcElixir.Plug`,
> `use RpcElixir.Handler`).

## Quick example

Define a handler module with a `@spec` following the RPC convention
(`call(input, context) :: {:ok, output} | {:error, error}`). `use
RpcElixir.Handler` is the recommended default. It captures the `@spec` AST so
the handler and router can live in the same Mix project without parallel-compiler
races (see [Handler compilation](#handler-compilation)):

```elixir
defmodule MyApp.Handlers.Users do
  use RpcElixir.Handler

  @type get_user_input :: %{id: integer()}
  @type user :: %{id: integer(), name: String.t()}

  @spec get_user(get_user_input(), RpcElixir.Context.t()) ::
          {:ok, user()} | {:error, :not_found}
  def get_user(%{id: id}, _ctx) do
    # ...
  end
end
```

The types are resolved from the compiled module's debug info. No compile-time
macro is required, and the router does this for you. To inspect the resolution
directly:

```elixir
alias RpcElixir.Types.FromSpec

{:ok, %{input: input, output: output, error: error}} =
  FromSpec.fetch_rpc(MyApp.Handlers.Users, :get_user)

# input  => %{kind: "object", fields: %{id: %{kind: "primitive", type: "integer"}}}
# output => %{kind: "object", fields: %{id: %{kind: "primitive", type: "integer"}, name: %{kind: "primitive", type: "string"}}}
# error  => %{kind: "primitive", type: "atom"}
```

## Handler compilation

`RpcElixir.Router` validates handler `@spec`s inside its `__before_compile__`
hook. It can read those specs two ways:

- **`use RpcElixir.Handler` (recommended default).** The macro captures the
  `@spec` AST into a `__rpc_specs__/0` accessor, and the router calls that
  accessor. The function-call edge forces the parallel compiler to finish the
  handler before the router's hook runs, so handlers and router can live in the
  **same Mix project**.
- **BEAM on disk (advanced).** Without `use RpcElixir.Handler`, the router reads
  specs from the handler's compiled BEAM via `Code.Typespec.fetch_specs/1`. In a
  single Mix project the parallel compiler may run the router's hook before
  in-progress handler BEAMs are flushed, producing spurious "no @spec" errors. To
  use this path reliably the handlers must live in a **separate Mix `path:` dep**
  so their BEAMs are on disk first. Prefer `use RpcElixir.Handler` unless you have
  a specific reason for the split.

## Type sources

Procedure types come from a compiled module's BEAM debug info. No compile-time
macro is required.

- **`RpcElixir.Types.FromSpec`** (recommended) reads classic `@spec`
  declarations via `Code.Typespec.fetch_specs/1`. Users write `@spec` next to
  their handlers. `FromSpec` reads them at runtime.
- **`RpcElixir.Types.FromInferred`** (experimental) reads signatures inferred
  by Elixir's set-theoretic type system from the `ExCk` BEAM chunk. Lossy by
  design (most arg types come back as `dynamic`), depends on private compiler
  internals that change every minor release. Useful for tracking the new type
  system as a public introspection API stabilizes.

  To use this backend, enable inference in your own `mix.exs`. Compiler
  options don't propagate from a dependency, so the target modules must be
  compiled with this option set:

  ```elixir
  defmodule MyApp.MixProject do
    use Mix.Project

    Code.compiler_options(infer_signatures: true)

    def project, do: [...]
  end
  ```

## Errors

Handler errors are *typed*. The `@spec` declares the error shape, the
dispatcher promotes the runtime value to an `%RpcError{}`, the codegen turns
it into `RpcError<Code, Details>` on the TypeScript side, and the client
throws an `RpcError` instance you can `catch` and discriminate by `code`.

### Supported error shapes

```elixir
# 1. Bare atom union - code only.
@spec get(input(), ctx()) :: {:ok, user()} | {:error, :not_found | :forbidden}
def get(_, _), do: {:error, :not_found}

# 2. Map with :code (atom union) and optional :message and extra detail fields.
@spec update(input(), ctx()) ::
        {:ok, user()}
        | {:error, %{code: :not_found | :email_taken, message: String.t(), field: String.t() | nil}}
def update(_, _), do: {:error, %{code: :email_taken, message: "in use", field: "email"}}
```

### Wire format

The dispatcher pulls `:code` and `:message` to the top of the JSON envelope.
Everything else ends up under `details`:

```elixir
{:error, %{code: :email_taken, message: "in use", field: "email"}}
```

→ `HTTP 400 {"error": {"code": "email_taken", "message": "in use", "details": {"field": "email"}}}`

### Generated TypeScript

```ts
import { RpcError } from "@elixir-ts-rpc/client";

export type UsersUpdateError = RpcError<
  "not_found" | "email_taken",
  { field: string | null }
>;

try {
  await client.users.update({ id, email });
} catch (err) {
  if (err instanceof RpcError) {
    err.code;          // "not_found" | "email_taken" | …
    err.message;       // human-readable string (also surfaces in stack traces)
    err.details?.field; // typed extras
  }
}
```

### Status codes

Typed errors default to **HTTP 400**. Framework-emitted errors carry their own
status (401 unauthorized, 403 forbidden, 404 procedure_not_found, 500 for
output_validation_failed / handler_error). To override, return a
`%RpcError{status: 422}` from your handler.

### Typed-error `:message` and `:details` are sent to the client verbatim

Whatever a handler puts in a typed error's `:message` and the extra detail fields
is serialized to the client **as-is**. This is *not* gated by the
`:expose_error_details` config. That flag only redacts the framework-generated
diagnostics on the unexpected-return / raised-exception paths (which become
`:handler_error`). For your own typed errors, never put internal diagnostics
(stack traces, SQL, secrets) in `:message` or `:details`. Treat both as
client-facing.

### `details` values must be JSON-native

The library serializes errors with Elixir 1.18+'s built-in `JSON` module, which
does **not** auto-encode `Date`, `DateTime`, `NaiveDateTime`, `Time`, or
`Decimal`. Placing any of those types in `details` **raises at serialization
time**, a runtime failure on the error path, not a compile-time check.
Pre-convert them to strings or numbers before building the `details` map.

```elixir
# bad - raises at runtime
{:error, %{code: :expired, details: %{at: ~U[2026-01-01 00:00:00Z]}}}

# good
{:error, %{code: :expired, details: %{at: DateTime.to_iso8601(~U[2026-01-01 00:00:00Z])}}}
```

### Anything else falls through

Returns that aren't an atom, an `%RpcError{}`, or a map with `:code` (e.g.
`{:error, {:bobo, :gaga}}`, `{:error, [code: :foo]}`, `{:error, "string"}`)
are treated as framework bugs: code becomes `:handler_error`, status is 500,
and the original value is `inspect`-ed into `details.reason` so JSON
serialization can't blow up. Type your errors explicitly to avoid this path.

## Documentation

- [Supported types](docs/supported-types.md) - inline shorthand, `@spec` AST
  forms, Ecto field mappings, custom types, and the pagination envelope.

## License

MIT - see [LICENSE](https://github.com/ostatni5/elixir-ts-rpc/blob/main/apps/rpc_elixir/LICENSE).
