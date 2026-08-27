defmodule BasicServer.Middleware.RequireUser do
  @moduledoc """
  Loads the current user from the session and assigns it to `ctx.assigns`.

  Halts with `:unauthorized` if no session, no `:user_id`, or the user lookup
  fails. App-level middleware — apps own their auth policy (session shape,
  user store, error semantics).
  """

  @behaviour RpcElixir.Middleware

  alias RpcElixir.{Resolution, RpcError}

  # Single source of truth: the code we halt with and the code we advertise to
  # codegen via rpc_error_codes/1 must stay in lockstep.
  @unauthorized :unauthorized

  @impl true
  def call(%Resolution{ctx: %{req: %{session: session}}} = res, _opts) when is_map(session) do
    with {:ok, user_id} <- fetch_user_id(session),
         {:ok, user} <- BasicServer.Users.get(user_id) do
      Resolution.assign(res, :current_user, user)
    else
      _ -> Resolution.halt(res, %RpcError{code: @unauthorized, message: "not logged in"})
    end
  end

  def call(res, _opts) do
    Resolution.halt(res, %RpcError{code: @unauthorized, message: "session not available"})
  end

  @impl true
  def rpc_error_codes(_opts), do: [@unauthorized]

  defp fetch_user_id(session) do
    case Map.get(session, :user_id) || Map.get(session, "user_id") do
      nil -> :error
      id -> {:ok, id}
    end
  end
end
