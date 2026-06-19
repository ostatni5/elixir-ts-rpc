defmodule RpcElixir.PlugTest.AssignEchoHandler do
  @moduledoc false

  @spec call(%{}, %{}) :: {:ok, %{captured_cookies: String.t()}}
  def call(_input, ctx), do: {:ok, ctx.assigns}
end
