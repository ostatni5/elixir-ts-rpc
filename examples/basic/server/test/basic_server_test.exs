defmodule BasicServerTest do
  use ExUnit.Case, async: true

  import Plug.Test
  import Plug.Conn

  @secret String.duplicate("a", 64)
  @session_key "_basic_session"

  defp make_conn(path, body \\ "{}") do
    :post
    |> conn(path, body)
    |> put_req_header("content-type", "application/json")
    |> Map.put(:secret_key_base, @secret)
  end

  defp call(conn) do
    opts = BasicServer.RootPlug.init(secret_key_base: @secret)
    BasicServer.RootPlug.call(conn, opts)
  end

  defp decode(conn), do: JSON.decode!(conn.resp_body)

  defp extract_session_cookie(conn) do
    conn
    |> get_resp_header("set-cookie")
    |> Enum.find(&String.contains?(&1, @session_key))
  end

  defp with_session_cookie(conn, cookie_string) do
    [cookie_kv | _] = String.split(cookie_string, ";")
    [name, value] = String.split(cookie_kv, "=", parts: 2)
    put_req_cookie(conn, String.trim(name), String.trim(value))
  end

  describe "auth.login" do
    test "valid credentials return user and set session cookie" do
      conn =
        make_conn("/auth/login", ~s({"username":"alice","password":"wonderland"}))
        |> call()

      assert conn.status == 200
      body = decode(conn)
      assert body["ok"]["id"] == "alice"
      assert body["ok"]["email"] == "alice@example.com"
      assert extract_session_cookie(conn) != nil
    end

    test "invalid credentials return 401" do
      conn =
        make_conn("/auth/login", ~s({"username":"alice","password":"wrong"}))
        |> call()

      assert conn.status == 401
      body = decode(conn)
      assert body["error"]["code"] == "unauthorized"
    end
  end

  describe "auth.me" do
    test "without session cookie returns 401" do
      conn = make_conn("/rpc/auth.me") |> call()
      assert conn.status == 401
      body = decode(conn)
      assert body["error"]["code"] == "unauthorized"
    end

    test "with valid session cookie returns current user" do
      login_conn =
        make_conn("/auth/login", ~s({"username":"alice","password":"wonderland"}))
        |> call()

      cookie = extract_session_cookie(login_conn)
      assert cookie != nil

      me_conn =
        make_conn("/rpc/auth.me")
        |> with_session_cookie(cookie)
        |> call()

      assert me_conn.status == 200
      body = decode(me_conn)
      assert body["ok"]["id"] == "alice"
      assert body["ok"]["email"] == "alice@example.com"
    end
  end

  describe "users.list" do
    test "with valid session returns list of users" do
      login_conn =
        make_conn("/auth/login", ~s({"username":"bob","password":"builder"}))
        |> call()

      cookie = extract_session_cookie(login_conn)

      list_conn =
        make_conn("/rpc/users.list")
        |> with_session_cookie(cookie)
        |> call()

      assert list_conn.status == 200
      body = decode(list_conn)
      users = body["ok"]["users"]
      assert is_list(users)
      assert length(users) == 2

      bob = Enum.find(users, &(&1["id"] == "bob"))
      # account_id is a 64-bit id sent as a string (branded Int64String) — it must
      # never serialize to a JSON number, which would silently lose precision.
      assert bob["account_id"] == "9007199254740993"
      assert is_binary(bob["account_id"])
    end
  end

  describe "users.get" do
    test "returns user for existing id" do
      login_conn =
        make_conn("/auth/login", ~s({"username":"alice","password":"wonderland"}))
        |> call()

      cookie = extract_session_cookie(login_conn)

      get_conn =
        make_conn("/rpc/users.get", ~s({"id":"alice"}))
        |> with_session_cookie(cookie)
        |> call()

      assert get_conn.status == 200
      body = decode(get_conn)
      assert body["ok"]["id"] == "alice"
      assert body["ok"]["email"] == "alice@example.com"
    end

    test "returns 404 for unknown id" do
      login_conn =
        make_conn("/auth/login", ~s({"username":"alice","password":"wonderland"}))
        |> call()

      cookie = extract_session_cookie(login_conn)

      get_conn =
        make_conn("/rpc/users.get", ~s({"id":"nobody"}))
        |> with_session_cookie(cookie)
        |> call()

      assert get_conn.status == 404
      body = decode(get_conn)
      assert body["error"]["code"] == "not_found"
    end
  end

  describe "users.update" do
    test "updates email for existing user" do
      login_conn =
        make_conn("/auth/login", ~s({"username":"alice","password":"wonderland"}))
        |> call()

      cookie = extract_session_cookie(login_conn)

      update_conn =
        make_conn("/rpc/users.update", ~s({"id":"alice","email":"new@example.com"}))
        |> with_session_cookie(cookie)
        |> call()

      assert update_conn.status == 200
      body = decode(update_conn)
      assert body["ok"]["id"] == "alice"
      assert body["ok"]["email"] == "new@example.com"
    end

    test "returns error for invalid email" do
      login_conn =
        make_conn("/auth/login", ~s({"username":"alice","password":"wonderland"}))
        |> call()

      cookie = extract_session_cookie(login_conn)

      update_conn =
        make_conn("/rpc/users.update", ~s({"id":"alice","email":"noemail"}))
        |> with_session_cookie(cookie)
        |> call()

      # :invalid_email is a typed handler error — the framework maps it to 400.
      assert update_conn.status == 400
      body = decode(update_conn)
      assert body["error"]["code"] == "invalid_email"
    end
  end

  describe "users.delete" do
    test "admin can delete a user" do
      login_conn =
        make_conn("/auth/login", ~s({"username":"alice","password":"wonderland"}))
        |> call()

      cookie = extract_session_cookie(login_conn)

      delete_conn =
        make_conn("/rpc/users.delete", ~s({"id":"bob"}))
        |> with_session_cookie(cookie)
        |> call()

      assert delete_conn.status == 200
      body = decode(delete_conn)
      assert body["ok"]["deleted"] == true
    end

    test "non-admin gets 403 forbidden" do
      login_conn =
        make_conn("/auth/login", ~s({"username":"bob","password":"builder"}))
        |> call()

      cookie = extract_session_cookie(login_conn)

      delete_conn =
        make_conn("/rpc/users.delete", ~s({"id":"alice"}))
        |> with_session_cookie(cookie)
        |> call()

      assert delete_conn.status == 403
      body = decode(delete_conn)
      assert body["error"]["code"] == "forbidden"
    end

    test "returns 404 for unknown user" do
      login_conn =
        make_conn("/auth/login", ~s({"username":"alice","password":"wonderland"}))
        |> call()

      cookie = extract_session_cookie(login_conn)

      delete_conn =
        make_conn("/rpc/users.delete", ~s({"id":"nobody"}))
        |> with_session_cookie(cookie)
        |> call()

      assert delete_conn.status == 404
      body = decode(delete_conn)
      assert body["error"]["code"] == "not_found"
    end
  end

  describe "auth.logout" do
    test "clears session; subsequent auth.me returns 401" do
      login_conn =
        make_conn("/auth/login", ~s({"username":"alice","password":"wonderland"}))
        |> call()

      cookie = extract_session_cookie(login_conn)

      logout_conn =
        make_conn("/auth/logout")
        |> with_session_cookie(cookie)
        |> call()

      assert logout_conn.status == 200
      cleared_cookie = extract_session_cookie(logout_conn)

      base_me = make_conn("/rpc/auth.me")

      me_conn =
        if cleared_cookie,
          do: base_me |> with_session_cookie(cleared_cookie) |> call(),
          else: base_me |> call()

      assert me_conn.status == 401
    end
  end
end
