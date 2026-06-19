defmodule BasicServer.Handlers.Users do
  @moduledoc "User procedure handlers."

  use RpcElixir.Handler

  @spec list(
          %{
            optional(:filter) => %{
              optional(:since) => DateTime.t(),
              optional(:until) => DateTime.t(),
              optional(:born_after) => Date.t()
            }
          },
          %{}
        ) ::
          {:ok,
           %{
             users: [
               %{
                 id: String.t(),
                 account_id: BasicServer.Types.Int64.t(),
                 email: String.t(),
                 created_at: DateTime.t(),
                 last_login_at: NaiveDateTime.t(),
                 birthday: Date.t() | nil
               }
             ],
             meta: %{
               generated_at: DateTime.t(),
               range: %{since: DateTime.t() | nil, until: DateTime.t() | nil}
             }
           }}
  def list(input, _ctx) do
    filter = Map.get(input, :filter, %{})
    since = Map.get(filter, :since)
    until_at = Map.get(filter, :until)
    born_after = Map.get(filter, :born_after)

    users =
      BasicServer.Users.list()
      |> Enum.filter(&within_created_range?(&1, since, until_at))
      |> Enum.filter(&born_after?(&1, born_after))
      |> Enum.map(
        &%{
          id: &1.id,
          account_id: &1.account_id,
          email: &1.email,
          created_at: &1.created_at,
          last_login_at: &1.last_login_at,
          birthday: &1.birthday
        }
      )

    {:ok,
     %{
       users: users,
       meta: %{
         generated_at: DateTime.utc_now(),
         range: %{since: since, until: until_at}
       }
     }}
  end

  defp within_created_range?(_user, nil, nil), do: true

  defp within_created_range?(%{created_at: created_at}, since, until_at) do
    after_since? = since == nil or DateTime.compare(created_at, since) != :lt
    before_until? = until_at == nil or DateTime.compare(created_at, until_at) != :gt
    after_since? and before_until?
  end

  defp born_after?(_user, nil), do: true
  defp born_after?(%{birthday: nil}, _cutoff), do: false
  defp born_after?(%{birthday: birthday}, cutoff), do: Date.compare(birthday, cutoff) == :gt

  @spec get(%{id: String.t()}, %{}) ::
          {:ok, %{id: String.t(), email: String.t()}} | {:error, :not_found}
  def get(%{id: id}, _ctx) do
    case BasicServer.Users.get(id) do
      {:ok, user} -> {:ok, %{id: user.id, email: user.email}}
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  @spec update(%{id: String.t(), email: String.t()}, %{}) ::
          {:ok, %{id: String.t(), email: String.t()}}
          | {:error,
             %{
               code: :not_found | :email_taken | :invalid_email,
               message: String.t(),
               field: String.t() | nil
             }}
  def update(%{id: id, email: email}, _ctx) do
    cond do
      not String.contains?(email, "@") ->
        {:error, %{code: :invalid_email, message: "must contain @", field: "email"}}

      email == "taken@example.com" ->
        {:error, %{code: :email_taken, message: "already in use", field: "email"}}

      true ->
        case BasicServer.Users.get(id) do
          {:ok, user} ->
            {:ok, %{id: user.id, email: email}}

          {:error, :not_found} ->
            {:error, %{code: :not_found, message: "user not found", field: nil}}
        end
    end
  end

  @spec delete(%{id: String.t()}, %{}) ::
          {:ok, %{deleted: boolean()}}
          | {:error, :not_found | :forbidden}
  def delete(%{id: id}, ctx) do
    # Deny by default: only an explicit admin match may delete.
    if match?(%{role: :admin}, ctx.assigns[:current_user]) do
      case BasicServer.Users.get(id) do
        {:ok, _} -> {:ok, %{deleted: true}}
        {:error, :not_found} -> {:error, :not_found}
      end
    else
      {:error, :forbidden}
    end
  end
end
