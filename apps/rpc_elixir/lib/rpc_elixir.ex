defmodule RpcElixir do
  @moduledoc """
  Elixir server-side library for [elixir-ts-rpc](https://github.com/ostatni5/elixir-ts-rpc),
  a typed RPC layer between Elixir servers and TypeScript clients.

  ## Status

  Early release (`0.0.1`), pre-1.0. APIs may change between minor versions.
  The full HTTP/Plug RPC stack has landed:

    * `RpcElixir.Context` / `RpcElixir.Resolution`, request-scoped context and
      result wrapper threaded through middleware into procedures
    * `RpcElixir.Types.FromSpec`, BEAM-reading type source
    * `RpcElixir.Router` / `RpcElixir.Handler`, procedure registration and
      compile-time `@spec` validation
    * `RpcElixir.Dispatcher` / `RpcElixir.Plug`, the lookup → validate →
      invoke → validate → serialize HTTP pipeline
    * `RpcElixir.Middleware`, request-scoped middleware framework
    * `RpcElixir.CustomType` / `RpcElixir.UnixMillis`, user-defined and branded
      wire types
    * TypeScript codegen via the `mix rpc.gen.ts` task and the
      `:elixir_ts_rpc` compiler

  Realtime transports (SSE, Phoenix Channels) are not built yet.

  ## Type sources

  Procedure types come from a compiled module's BEAM debug info, no
  compile-time macro is required. Two backends are available:

    * `RpcElixir.Types.FromSpec` (recommended) reads classic `@spec`
      declarations via `Code.Typespec.fetch_specs/1`.
    * `RpcElixir.Types.FromInferred` (experimental) reads signatures inferred
      by Elixir's set-theoretic type system from the `ExCk` BEAM chunk. Lossy
      by design and depends on private compiler internals that change every
      minor release. To use it, enable inference in your own `mix.exs`:

          defmodule MyApp.MixProject do
            use Mix.Project

            Code.compiler_options(infer_signatures: true)

            def project, do: [...]
          end

  See the [README](readme.html) and the supported-types guide for details on
  inline shorthand, `@spec` AST forms, Ecto field mappings, and custom types.
  """

  alias RpcElixir.{Context, Dispatcher, Resolution}

  @doc """
  In-process convenience caller for tests and server-to-server invocations.

  Builds a minimal `%Resolution{}` from `path` and `ctx`, dispatches it, and
  returns the resolution's `:result`.
  """
  @spec call(module(), String.t(), map(), Context.t()) :: Dispatcher.result()
  def call(router, path, input, ctx \\ %Context{}) do
    Dispatcher.dispatch(router, path, input, %Resolution{procedure: path, ctx: ctx}).result
  end
end
