defmodule RpcElixir do
  @moduledoc """
  Elixir server library for [elixir-ts-rpc](https://github.com/ostatni5/elixir-ts-rpc) —
  a typed RPC layer between Elixir and TypeScript. Pre-1.0, so APIs may change.
  Start with [Getting started](getting-started.md).

  ## Type sources

  Types come from a compiled module's BEAM debug info. No compile-time macro is
  required. Two backends exist:

    * `RpcElixir.Types.FromSpec` (recommended) reads classic `@spec`
      declarations via `Code.Typespec.fetch_specs/1`.
    * `RpcElixir.Types.FromInferred` (experimental) is lossy. See its module
      docs.

  See the [README](readme.html) and [Supported types](supported-types.md).
  """

  alias RpcElixir.{Context, Dispatcher, Resolution}

  @doc """
  In-process caller for tests and server-to-server invocations.

  Builds a minimal `%Resolution{}` from `path` and `ctx`. Dispatches it, then
  returns the resolution's `:result`.
  """
  @spec call(module(), String.t(), map(), Context.t()) :: Dispatcher.result()
  def call(router, path, input, ctx \\ %Context{}) do
    Dispatcher.dispatch(router, path, input, %Resolution{procedure: path, ctx: ctx}).result
  end
end
