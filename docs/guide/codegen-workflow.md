# Codegen workflows

Three ways to regenerate the TypeScript client from your `@spec`s.

## Compiler hook: the usual choice

Add `:elixir_ts_rpc` to `compilers:`. Then point it at your router and output
file:

```elixir
# mix.exs
compilers: Mix.compilers() ++ [:elixir_ts_rpc]

# config/config.exs
config :elixir_ts_rpc,
  router: MyApp.Router,
  out: Path.expand("../client/src/rpc.gen.ts", __DIR__)
```

The client regenerates on every `mix compile`. The hook only writes when the
output changed. The explicit task writes every time.

The hook needs both `:router` and `:out`. If either is missing, it silently
does nothing. You get no error and no file.

`mix clean` deletes the generated client. The hook registers it as a build
manifest.

### Auto-reload with Phoenix

A request-triggered reload alone does not regenerate the client. Phoenix reruns
only the endpoint's `:reloadable_compilers`. That list excludes
`:elixir_ts_rpc` by default. Add it yourself:

```elixir
# lib/my_app_web/endpoint.ex
reloadable_compilers: [:gettext, :elixir, :app, :elixir_ts_rpc]
```

With that line in place, the loop is:

1. You edit a handler or its `@spec`.
2. Phoenix's dev code reloader recompiles changed modules on the next request.
3. The `:elixir_ts_rpc` compiler regenerates `rpc.gen.ts`.
4. Vite hot-reloads the client with the new types.

Add the compiler after Phoenix's own. Keep `code_reloader: true`, the
`config/dev.exs` default. Put `:out` inside your Vite client's `src/`. The dev
server then watches that file:

```elixir
# mix.exs
compilers: [:phoenix_live_view] ++ Mix.compilers() ++ [:elixir_ts_rpc],
listeners: [Phoenix.CodeReloader]
```

The `listeners:` entry is separate. It lets the reloader notice compiles you
run yourself, in another terminal. It does not widen `:reloadable_compilers`.

The [Phoenix example](/guide/examples) uses this compiler setup. While you
iterate, the watch task is the better choice. It regenerates on save, without
waiting for a request.

## Watch task: while iterating against the TS dev server

```bash
mix rpc.gen.ts.watch --router MyApp.Router --out path/to/rpc.gen.ts
```

This regenerates on each Elixir source change. Vite and HMR see the new types
at once. With `expose`, that includes adding a spec'd arity-2 function to a
handler: the new procedure reaches the client without a router edit. It watches `lib` by default. Pass `--dir` to change that. Repeat it
for more directories. It needs the optional dep
`{:file_system, "~> 1.0", only: :dev}`.

It reacts to `.ex` files only. Edits to `.exs` files are ignored. Rapid changes
are debounced by 200 ms.

## Explicit task: for CI and one-off generation

```bash
mix rpc.gen.ts --router MyApp.Router --out path/to/rpc.gen.ts
```

Treat the generated client as a build artifact. Gitignore it. In CI, generate
it, then typecheck.

It also embeds one absolute `file://` path per procedure, the link from each
method back to its handler line. Editors only detect links in that form. Those
paths belong to the machine that ran the generator, so a committed client churns
its diff on every other machine.

::: tip
The basic example's CI generates the client, then typechecks it. See the
[`integration` job](https://github.com/ostatni5/elixir-ts-rpc/blob/main/.github/workflows/ci.yml).
:::

## Task flags

`mix rpc.gen.ts` accepts `--router`, `--out`, and `--client-import`.
`mix rpc.gen.ts.watch` accepts those three plus `--dir`, which you can repeat.
Both accept `--help`. The two differ on a bad flag. `mix rpc.gen.ts` raises.
The watch task ignores it in silence, so check your spelling.

`--client-import` sets the package name in the generated import statement. It
defaults to `@elixir-ts-rpc/client`. Use it to point the import at your own
re-export or a vendored copy.

The compiler hook cannot set it. The hook reads only `:router` and `:out`. So a
project with a custom import name has to use the task.
