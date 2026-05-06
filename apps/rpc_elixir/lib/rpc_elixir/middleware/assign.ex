defmodule RpcElixir.Middleware.Assign do
  @moduledoc """
  Built-in middleware that puts static values into `ctx.assigns`.

  Useful for stamping a procedure with request-shape metadata (source channel,
  feature flag overrides, fixture data in tests) without touching the handler.

  ## Usage

      procedure "billing.charge", &MyApp.Billing.charge/2,
        middleware: [
          {RpcElixir.Middleware.Assign, source: :api, environment: :prod}
        ]

  Each `{key, value}` pair in `opts` becomes an entry in `ctx.assigns`. Existing
  assigns under the same key are overwritten.
  """

  @behaviour RpcElixir.Middleware

  alias RpcElixir.Resolution

  @impl true
  def call(%Resolution{} = res, opts) when is_list(opts) do
    Enum.each(opts, fn
      {key, _} when is_atom(key) ->
        :ok

      {key, _} ->
        raise ArgumentError, "RpcElixir.Middleware.Assign expects atom keys, got: #{inspect(key)}"
    end)

    Enum.reduce(opts, res, fn {key, value}, acc ->
      Resolution.assign(acc, key, value)
    end)
  end
end
