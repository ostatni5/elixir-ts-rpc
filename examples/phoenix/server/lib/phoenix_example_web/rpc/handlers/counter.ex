defmodule PhoenixExampleWeb.Rpc.Handlers.Counter do
  @moduledoc """
  A per-user counter — the example's mutating procedure.

  Handlers can't write to the HTTP response (no cookies/headers), but they may
  write to the database, so a state-changing procedure like `adjust` fits the
  RPC contract fine. The counter is scoped to the authenticated user from
  Phoenix's `current_scope`.
  """

  use RpcElixir.Handler

  alias PhoenixExample.Accounts
  alias RpcElixir.Context

  @spec get(%{}, Context.t()) :: {:ok, %{count: integer()}}
  def get(_input, %Context{assigns: %{current_user: user}}) do
    {:ok, %{count: user.count}}
  end

  @spec adjust(%{delta: integer()}, Context.t()) :: {:ok, %{count: integer()}}
  def adjust(%{delta: delta}, %Context{assigns: %{current_user: user}}) do
    {:ok, %{count: Accounts.adjust_user_count(user, delta)}}
  end
end
