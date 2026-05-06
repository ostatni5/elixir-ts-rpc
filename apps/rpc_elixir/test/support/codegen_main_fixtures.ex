defmodule RpcElixir.ManifestFixtures.Address do
  @moduledoc false
  @type t :: %__MODULE__{street: String.t(), city: String.t()}
  defstruct [:street, :city]
end

defmodule RpcElixir.ManifestFixtures.Handlers do
  @moduledoc false

  @doc "Get a user by id."
  @spec get_user(
          %{required(:id) => String.t(), optional(:include_deleted) => boolean()},
          %{}
        ) ::
          {:ok,
           %{
             id: String.t(),
             name: String.t(),
             score: float(),
             tags: [String.t()],
             born_on: Date.t(),
             address: RpcElixir.ManifestFixtures.Address.t()
           }}
          | {:error, :not_found | :unauthorized}
  def get_user(_input, _ctx),
    do:
      {:ok,
       %{
         id: "1",
         name: "Alice",
         score: 1.0,
         tags: [],
         born_on: ~D[2000-01-01],
         address: %RpcElixir.ManifestFixtures.Address{street: "Main", city: "NY"}
       }}

  @doc "List users."
  @spec list_users(%{optional(:limit) => integer()}, %{}) ::
          {:ok, [%{id: String.t(), name: String.t()}]}
  def list_users(_input, _ctx), do: {:ok, []}

  @spec create_user(
          %{name: String.t(), role: :admin | :member | :viewer, created_at: DateTime.t()},
          %{}
        ) ::
          {:ok, %{id: String.t()}} | {:error, :conflict}
  def create_user(_input, _ctx), do: {:ok, %{id: "new"}}
end
