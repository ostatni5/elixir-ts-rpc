defmodule PhoenixExampleWeb.Rpc.Handlers.Users do
  @moduledoc """
  User procedures backed by the real `Accounts` context and database — the same
  data Phoenix's auth, registration, and settings pages operate on.
  """

  use RpcElixir.Handler

  alias PhoenixExample.Accounts
  alias RpcElixir.Context

  @type user_view :: %{
          id: integer(),
          email: String.t(),
          confirmed_at: DateTime.t() | nil,
          inserted_at: DateTime.t()
        }

  @spec list(%{}, Context.t()) :: {:ok, %{users: [user_view()]}}
  def list(_input, _ctx) do
    {:ok, %{users: Enum.map(Accounts.list_users(), &to_view/1)}}
  end

  @spec get(%{id: integer()}, Context.t()) :: {:ok, user_view()} | {:error, :not_found}
  def get(%{id: id}, _ctx) do
    case Accounts.fetch_user(id) do
      {:ok, user} -> {:ok, to_view(user)}
      :error -> {:error, :not_found}
    end
  end

  defp to_view(user) do
    %{
      id: user.id,
      email: user.email,
      confirmed_at: user.confirmed_at,
      inserted_at: user.inserted_at
    }
  end
end
