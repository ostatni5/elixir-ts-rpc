defmodule PhoenixExampleWeb.Rpc.Handlers.Demo do
  @moduledoc """
  Procedures that exist only to exercise the client's request log: one that takes
  a while to resolve (so its entry sits "pending" for ~5s before flipping to
  "ok"), and one that always fails with a domain error (so an entry flips to
  "error"). Not something a real app would ship.
  """

  use RpcElixir.Handler

  alias RpcElixir.Context

  @slow_ms 5_000

  @spec slow(%{}, Context.t()) :: {:ok, %{slept_ms: integer()}}
  def slow(_input, _ctx) do
    Process.sleep(@slow_ms)
    {:ok, %{slept_ms: @slow_ms}}
  end

  # Always errors, but the spec still needs a success arm to describe the wire.
  @spec fail(%{}, Context.t()) :: {:ok, %{}} | {:error, :demo_failure}
  def fail(_input, _ctx) do
    {:error, :demo_failure}
  end
end
