defmodule RpcElixir.JSON do
  @moduledoc false

  # Elixir's built-in JSON module arrived in 1.18. On 1.17 we fall back to Jason,
  # which consumers on that version add to their own deps (see `deps/0` in mix.exs).
  # Resolved at compile time, so call sites pay nothing for the indirection.
  @backend (cond do
              Code.ensure_loaded?(JSON) ->
                JSON

              Code.ensure_loaded?(Jason) ->
                Jason

              true ->
                raise "elixir_ts_rpc needs Elixir's built-in JSON (1.18+), " <>
                        "or `{:jason, \"~> 1.4\"}` in your deps on Elixir 1.17"
            end)

  defdelegate encode!(term), to: @backend
  defdelegate decode(binary), to: @backend
  defdelegate decode!(binary), to: @backend
end
