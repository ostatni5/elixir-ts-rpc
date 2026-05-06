defmodule PhoenixExampleWeb.RpcIntegrationTest do
  @moduledoc """
  Proves the RPC pipeline reuses Phoenix's authentication: the same
  `current_scope` that Phoenix's generated auth populates is what `RequireUser`
  authorizes against, no RPC-specific auth code.
  """

  use PhoenixExampleWeb.ConnCase

  import PhoenixExample.AccountsFixtures

  defp rpc(conn, procedure, input \\ %{}) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post("/rpc/#{procedure}", Jason.encode!(input))
  end

  test "an unauthenticated call is rejected with a typed unauthorized error", %{conn: conn} do
    assert %{"error" => %{"code" => "unauthorized"}} =
             conn |> rpc("users.list") |> json_response(401)
  end

  test "a state-changing call without a CSRF token is rejected by Phoenix's protect_from_forgery",
       %{conn: conn} do
    # ConnCase's conn has CSRF skipped (set in Phoenix.ConnTest.build_conn). Flip
    # it back on to prove the :rpc pipeline's protect_from_forgery actually guards
    # RPC. A tokenless POST raises, which the endpoint turns into a 403.
    conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> Plug.Conn.put_private(:plug_skip_csrf_protection, false)
      |> put_req_header("content-type", "application/json")

    assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn ->
      post(conn, "/rpc/users.list", Jason.encode!(%{}))
    end
  end

  test "auth.me reflects the logged-in user", %{conn: conn} do
    user = user_fixture()

    assert %{"ok" => %{"email" => email, "id" => id}} =
             conn |> log_in_user(user) |> rpc("auth.me") |> json_response(200)

    assert email == user.email
    assert id == user.id
  end

  test "users.list returns real database users for an authenticated call", %{conn: conn} do
    user = user_fixture()

    assert %{"ok" => %{"users" => users}} =
             conn |> log_in_user(user) |> rpc("users.list") |> json_response(200)

    assert Enum.any?(users, &(&1["email"] == user.email))
  end

  test "users.get returns a user by id for an authenticated call", %{conn: conn} do
    user = user_fixture()

    assert %{"ok" => %{"id" => id, "email" => email}} =
             conn |> log_in_user(user) |> rpc("users.get", %{id: user.id}) |> json_response(200)

    assert id == user.id
    assert email == user.email
  end

  test "users.get returns a typed not_found error for a missing id", %{conn: conn} do
    user = user_fixture()

    assert %{"error" => %{"code" => "not_found"}} =
             conn |> log_in_user(user) |> rpc("users.get", %{id: 999_999}) |> json_response(404)
  end

  test "counter.adjust mutates the per-user counter and returns the new value", %{conn: conn} do
    user = user_fixture()
    conn = log_in_user(conn, user)

    assert %{"ok" => %{"count" => 0}} = conn |> rpc("counter.get") |> json_response(200)
    assert %{"ok" => %{"count" => 1}} = conn |> rpc("counter.adjust", %{delta: 1}) |> json_response(200)
    assert %{"ok" => %{"count" => 4}} = conn |> rpc("counter.adjust", %{delta: 3}) |> json_response(200)
    assert %{"ok" => %{"count" => 2}} = conn |> rpc("counter.adjust", %{delta: -2}) |> json_response(200)

    # The new value is persisted, not just echoed.
    assert %{"ok" => %{"count" => 2}} = conn |> rpc("counter.get") |> json_response(200)
  end
end
