defmodule BasicServer.Handlers.Auth do
  @moduledoc "Auth procedure handlers."

  use RpcElixir.Handler

  @spec me(%{}, %{}) ::
          {:ok, %{id: String.t(), email: String.t()}}
  def me(_input, ctx) do
    user = ctx.assigns[:current_user]
    {:ok, %{id: user.id, email: user.email}}
  end
end
