defmodule PhoenixExampleWeb.Rpc.Middleware.RequireUser do
  @moduledoc """
  Authenticates an RPC call using Phoenix's `current_scope`.

  The scope is lifted from `conn.assigns.current_scope` by
  `PhoenixExampleWeb.Rpc.Context.build/1`. It is a
  `PhoenixExample.Accounts.Scope` when a user is logged in and `nil` otherwise
  (that's what `Scope.for_user(nil)` returns in the generated auth).

  On success the user is assigned to `ctx.assigns.current_user` for handlers;
  otherwise the call halts with a typed `:unauthorized` error.
  """

  @behaviour RpcElixir.Middleware

  alias RpcElixir.{Resolution, RpcError}

  # Single source of truth: the code we halt with and the code we advertise to
  # codegen via rpc_error_codes/1 must stay in lockstep.
  @unauthorized :unauthorized

  @impl true
  def call(%Resolution{ctx: %{assigns: %{current_scope: %{user: user}}}} = res, _opts)
      when not is_nil(user) do
    Resolution.assign(res, :current_user, user)
  end

  def call(res, _opts) do
    Resolution.halt(res, %RpcError{code: @unauthorized, message: "not logged in"})
  end

  @impl true
  def rpc_error_codes(_opts), do: [@unauthorized]
end
