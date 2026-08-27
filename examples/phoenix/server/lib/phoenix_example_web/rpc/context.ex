defmodule PhoenixExampleWeb.Rpc.Context do
  @moduledoc """
  Bridges Phoenix's authentication into the RPC pipeline.

  Phoenix's generated `UserAuth.fetch_current_scope_for_user/2` plug runs before
  the RPC plug (see the `:rpc` pipeline in the router) and assigns
  `conn.assigns.current_scope`. This builder lifts that scope into the RPC
  `Context` so RPC middleware/handlers reuse the exact same authentication the
  rest of the Phoenix app uses — no separate session parsing or user lookup.

  `RpcElixir.Plug` only overwrites the `:req` field on the returned context, so
  the `:assigns` set here are preserved.
  """

  def build(conn) do
    %RpcElixir.Context{assigns: %{current_scope: conn.assigns[:current_scope]}}
  end
end
