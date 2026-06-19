# Seeds a confirmed demo user you can log in with via Phoenix's login page.
#
#     mix run priv/repo/seeds.exs
#
# Credentials: demo@example.com / demopassword123

alias PhoenixExample.{Accounts, Repo}
alias PhoenixExample.Accounts.User

email = "demo@example.com"
password = "demopassword123"

unless Accounts.get_user_by_email(email) do
  {:ok, user} = Accounts.register_user(%{email: email})
  {:ok, {user, _expired}} = Accounts.update_user_password(user, %{password: password})

  # Confirm the account so the demo user is in a clean, fully-onboarded state.
  user |> User.confirm_changeset() |> Repo.update!()

  IO.puts("Seeded demo user: #{email} / #{password}")
end
