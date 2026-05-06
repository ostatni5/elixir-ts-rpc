defmodule RpcElixir.PlugSessionFixtures.Handlers do
  @moduledoc false

  @spec noop(%{}, %{}) :: {:ok, %{ok: boolean()}} | {:error, :noop}
  def noop(_input, _ctx), do: {:ok, %{ok: true}}

  @spec me(%{}, %{}) :: {:ok, %{id: integer()}} | {:error, :noop}
  def me(_input, ctx) do
    user = ctx.assigns[:current_user]
    {:ok, %{id: user.id}}
  end
end

defmodule RpcElixir.PlugSessionFixtures.FakeUsers do
  @moduledoc false

  @users %{
    1 => %{id: 1, role: :user},
    2 => %{id: 2, role: :admin}
  }

  def get(id) when is_integer(id) do
    case Map.fetch(@users, id) do
      {:ok, user} -> {:ok, user}
      :error -> {:error, :not_found}
    end
  end

  def get(id) when is_binary(id) do
    case Integer.parse(id) do
      {int_id, ""} -> get(int_id)
      _ -> {:error, :not_found}
    end
  end

  def get(id) when is_float(id), do: get(trunc(id))

  def get(_), do: {:error, :not_found}
end
