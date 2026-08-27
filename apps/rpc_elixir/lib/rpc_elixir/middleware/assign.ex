defmodule RpcElixir.Middleware.Assign do
  @moduledoc """
  Built-in middleware that puts static values into `ctx.assigns`.

  Use it to stamp a procedure with fixed metadata. The handler stays unchanged.

  ## Usage

      procedure "billing.charge", &MyApp.Billing.charge/2,
        middleware: [
          {RpcElixir.Middleware.Assign, source: :api, environment: :prod}
        ]

  Each `{key, value}` in `opts` becomes a `ctx.assigns` entry. Existing keys are overwritten.
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
