defmodule RpcElixir.PlugSessionTest.SetSessionMiddleware do
  @moduledoc false
  @behaviour RpcElixir.Middleware

  alias RpcElixir.Resolution

  @impl true
  def call(%Resolution{} = res, opts) do
    case Keyword.get(opts, :action) do
      :set_user ->
        user_id = Keyword.fetch!(opts, :user_id)
        Resolution.put_session(res, :user_id, user_id)

      :logout ->
        Resolution.clear_session(res)

      _ ->
        res
    end
  end
end

defmodule RpcElixir.PlugSessionTest.RequireUser do
  @moduledoc false
  @behaviour RpcElixir.Middleware

  alias RpcElixir.PlugSessionFixtures.FakeUsers
  alias RpcElixir.{Resolution, RpcError}

  @impl true
  def call(%Resolution{ctx: %{req: %{session: session}}} = res, _opts) do
    case Map.get(session, :user_id) || Map.get(session, "user_id") do
      nil ->
        Resolution.halt(res, %RpcError{code: :unauthorized, message: "not logged in"})

      user_id ->
        case FakeUsers.get(user_id) do
          {:ok, user} -> Resolution.assign(res, :current_user, user)
          _ -> Resolution.halt(res, %RpcError{code: :unauthorized, message: "user not found"})
        end
    end
  end

  def call(res, _opts) do
    Resolution.halt(res, %RpcError{code: :unauthorized, message: "session not available"})
  end
end

defmodule RpcElixir.PlugSessionTest.RequireAdmin do
  @moduledoc false
  @behaviour RpcElixir.Middleware

  alias RpcElixir.{Resolution, RpcError}

  @impl true
  def call(%Resolution{} = res, _opts) do
    case Map.get(res.ctx.assigns, :current_user) do
      %{role: :admin} -> res
      _ -> Resolution.halt(res, %RpcError{code: :forbidden, message: "admin only"})
    end
  end
end

defmodule RpcElixir.PlugSessionTest.Router do
  @moduledoc false
  use RpcElixir.Router

  alias RpcElixir.PlugSessionFixtures.Handlers
  alias RpcElixir.PlugSessionTest.{RequireAdmin, RequireUser, SetSessionMiddleware}

  procedure "login.user", &Handlers.noop/2,
    middleware: [{SetSessionMiddleware, action: :set_user, user_id: 1}]

  procedure "login.admin", &Handlers.noop/2,
    middleware: [{SetSessionMiddleware, action: :set_user, user_id: 2}]

  procedure "logout", &Handlers.noop/2, middleware: [{SetSessionMiddleware, action: :logout}]

  procedure "me", &Handlers.me/2, middleware: [RequireUser]

  procedure "admin.action", &Handlers.noop/2, middleware: [RequireUser, RequireAdmin]
end

defmodule RpcElixir.PlugSessionTest.Pipeline do
  @moduledoc false
  use Plug.Builder

  plug Plug.Session,
    store: :cookie,
    key: "_test_session",
    signing_salt: "test_salt_1234567890",
    encryption_salt: "test_enc_salt_1234567890"

  plug :fetch_session

  plug RpcElixir.Plug, router: RpcElixir.PlugSessionTest.Router
end

defmodule RpcElixir.PlugSessionTest do
  use ExUnit.Case, async: true

  import Plug.Test
  import Plug.Conn

  alias RpcElixir.JSON
  alias RpcElixir.PlugSessionTest.Pipeline

  @secret String.duplicate("a", 64)

  defp make_conn(path) do
    :post
    |> conn(path, "{}")
    |> put_req_header("content-type", "application/json")
    |> Map.put(:secret_key_base, @secret)
  end

  defp call(conn) do
    Pipeline.call(conn, Pipeline.init([]))
  end

  defp decode_body(conn), do: JSON.decode!(conn.resp_body)

  defp extract_session_cookie(conn) do
    conn
    |> get_resp_header("set-cookie")
    |> Enum.find(&String.contains?(&1, "_test_session"))
  end

  defp with_session_cookie(conn, cookie_string) do
    [cookie_kv | _] = String.split(cookie_string, ";")
    [name, value] = String.split(cookie_kv, "=", parts: 2)
    put_req_cookie(conn, String.trim(name), String.trim(value))
  end

  describe "clear_session sentinel isolation" do
    test "logout via clear_session sets resp_session_clear, not a sentinel key" do
      alias RpcElixir.Resolution
      res = %Resolution{procedure: "logout"}
      cleared = Resolution.clear_session(res)
      refute Map.has_key?(cleared.resp_session, :__clear__)
      assert cleared.resp_session_clear == true
    end
  end

  describe "session integration" do
    test "call me without session cookie returns 401" do
      conn = make_conn("/rpc/me") |> call()
      assert conn.status == 401
      body = decode_body(conn)
      assert body["error"]["code"] == "unauthorized"
    end

    test "login.user sets session cookie" do
      conn = make_conn("/rpc/login.user") |> call()
      assert conn.status == 200
      assert extract_session_cookie(conn) != nil
    end

    test "me with valid session from login.user returns 200 with user id" do
      login_conn = make_conn("/rpc/login.user") |> call()
      assert login_conn.status == 200
      cookie = extract_session_cookie(login_conn)
      assert cookie != nil

      me_conn =
        "/rpc/me"
        |> make_conn()
        |> with_session_cookie(cookie)
        |> call()

      assert me_conn.status == 200
      body = decode_body(me_conn)
      assert body["ok"]["id"] == 1
    end

    test "logout clears session, subsequent me returns 401" do
      login_conn = make_conn("/rpc/login.user") |> call()
      cookie = extract_session_cookie(login_conn)

      logout_conn =
        "/rpc/logout"
        |> make_conn()
        |> with_session_cookie(cookie)
        |> call()

      assert logout_conn.status == 200
      cleared_cookie = extract_session_cookie(logout_conn)

      base_me_conn = "/rpc/me" |> make_conn()

      me_conn =
        if cleared_cookie,
          do: base_me_conn |> with_session_cookie(cleared_cookie) |> call(),
          else: base_me_conn |> call()

      assert me_conn.status == 401
    end

    test "RequireAdmin - regular user cannot access admin procedure (403)" do
      login_conn = make_conn("/rpc/login.user") |> call()
      cookie = extract_session_cookie(login_conn)

      admin_conn =
        "/rpc/admin.action"
        |> make_conn()
        |> with_session_cookie(cookie)
        |> call()

      assert admin_conn.status == 403
      body = decode_body(admin_conn)
      assert body["error"]["code"] == "forbidden"
    end

    test "RequireAdmin - admin user can access admin procedure (200)" do
      login_conn = make_conn("/rpc/login.admin") |> call()
      cookie = extract_session_cookie(login_conn)

      admin_conn =
        "/rpc/admin.action"
        |> make_conn()
        |> with_session_cookie(cookie)
        |> call()

      assert admin_conn.status == 200
    end
  end
end
