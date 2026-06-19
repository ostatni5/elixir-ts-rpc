# Codegen workflows

Three mechanisms regenerate the TypeScript client from your `@spec`s. They do
the same work. Pick by situation.

## Compiler hook: the steady-state default

Add `:elixir_ts_rpc` to your `compilers:` list. The client regenerates on every
`mix compile`, so it stays in sync with your `@spec`s with zero extra processes.

This is the recommended default for ordinary development.

## Auto-reload with Phoenix

In a Phoenix app the compiler hook gives you a hands-off loop: edit a handler or
its `@spec` and the regenerated client is ready for the browser, no extra watcher
to run. Phoenix's dev code reloader recompiles your changed Elixir, the appended
`:elixir_ts_rpc` compiler regenerates the client, and the Vite dev server
hot-reloads it. The [Phoenix example](/guide/examples) is wired exactly this way.

Three touchpoints set it up.

**1. Append the compiler in `mix.exs`**, after the standard compilers, so it
regenerates from freshly built BEAM:

```elixir
def project do
  [
    # ...
    compilers: [:phoenix_live_view] ++ Mix.compilers() ++ [:elixir_ts_rpc],
    listeners: [Phoenix.CodeReloader]
  ]
end
```

**2. Point the compiler at your router and output file** in `config/config.exs`:

```elixir
config :elixir_ts_rpc,
  router: MyAppWeb.RpcRouter,
  out: Path.expand("../../client/src/rpc.gen.ts", __DIR__)
```

Put `:out` inside your Vite client's `src/` so the dev server watches it. Add the
optional `{:file_system, "~> 1.0", only: :dev}` dependency too.

**3. Keep Phoenix's dev code reloader on**, the default in `config/dev.exs`:

```elixir
config :my_app, MyAppWeb.Endpoint, code_reloader: true
```

### The reload chain

1. You edit a handler or its `@spec`.
2. Phoenix's code reloader recompiles the changed modules.
3. The `:elixir_ts_rpc` compiler regenerates `rpc.gen.ts`, but **only when the
   generated output actually changed**, so unrelated edits don't churn the file.
4. Vite sees the file change and hot-reloads the client with the new types.

::: tip Regenerates on the next request
Phoenix's code reloader recompiles on the next request to the app, so the client
regenerates the next time the browser hits Phoenix. If you want regeneration the
instant you save, independent of any request, run `mix rpc.gen.ts.watch`
alongside the server instead. That is the Watch task below, which uses the same
`:file_system` dep.
:::

## Watch task: while iterating against the TS dev server

```bash
mix rpc.gen.ts.watch
```

Recompiles and regenerates on each Elixir source change so the Vite/HMR side
picks up new types immediately. Best when you're moving fast between Elixir and
the browser. Requires the optional `:file_system` dependency.

## Explicit task: for CI and one-off generation

```bash
mix rpc.gen.ts --router MyApp.Router --out path/to/rpc.gen.ts
```

Use this in CI to verify the committed `rpc.gen.ts` is up to date. Generate it,
then fail the build if `git diff` is non-empty. It also works for a one-off
regeneration.

::: tip
The basic example's CI does exactly this. It regenerates the client from the
router and typechecks it, so a drifted spec breaks the build. See the
[`integration` job](https://github.com/ostatni5/elixir-ts-rpc/blob/main/.github/workflows/ci.yml).
:::
