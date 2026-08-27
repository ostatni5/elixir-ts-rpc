defmodule PhoenixExampleWeb.Rpc.Handlers.Auth do
  @moduledoc """
  Read-only auth procedure.

  Returns the user that Phoenix authenticated for this request. It only *reads*
  the scope, so it fits the typed RPC contract cleanly — login/logout, which
  must mutate the session cookie, stay in Phoenix's generated controllers.
  """

  use RpcElixir.Handler

  alias RpcElixir.Context

  @spec me(%{}, Context.t()) ::
          {:ok, %{id: integer(), email: String.t(), confirmed_at: DateTime.t() | nil}}
  def me(_input, %Context{assigns: %{current_user: user}}) do
    {:ok, %{id: user.id, email: user.email, confirmed_at: user.confirmed_at}}
  end
end
