defmodule BasicServer.Users do
  @moduledoc "In-memory user store for the basic demo."

  @users %{
    "alice" => %{
      id: "alice",
      account_id: 9_223_372_036_854_775_123,
      email: "alice@example.com",
      role: :admin,
      password: "wonderland",
      created_at: ~U[2024-03-15 09:24:00Z],
      last_login_at: ~N[2026-05-08 08:12:43],
      birthday: ~D[1990-07-21]
    },
    "bob" => %{
      id: "bob",
      account_id: 9_007_199_254_740_993,
      email: "bob@example.com",
      role: :user,
      password: "builder",
      created_at: ~U[2025-01-02 14:50:00Z],
      last_login_at: ~N[2026-05-07 19:03:11],
      birthday: nil
    }
  }

  @spec authenticate(String.t(), String.t()) :: {:ok, map()} | {:error, :invalid}
  def authenticate(username, password) do
    case Map.get(@users, username) do
      %{password: ^password} = user -> {:ok, Map.delete(user, :password)}
      _ -> {:error, :invalid}
    end
  end

  @spec get(String.t()) :: {:ok, map()} | {:error, :not_found}
  def get(id) do
    case Map.get(@users, id) do
      nil -> {:error, :not_found}
      user -> {:ok, Map.delete(user, :password)}
    end
  end

  @spec list() :: [map()]
  def list do
    @users
    |> Map.values()
    |> Enum.map(&Map.delete(&1, :password))
  end
end
