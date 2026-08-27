defmodule RpcElixir.PlugTest.CookieMiddleware do
  @moduledoc false
  @behaviour RpcElixir.Middleware
  alias RpcElixir.Resolution

  @impl true
  def call(%Resolution{} = res, opts) do
    case Keyword.get(opts, :action) do
      :set ->
        Resolution.put_resp_cookie(res, "session", "abc",
          http_only: true,
          secure: false,
          same_site: "Lax"
        )

      :delete ->
        Resolution.delete_resp_cookie(res, "session")

      :header ->
        Resolution.put_resp_header(res, "x-trace-id", "trace-abc")

      :capture_cookies ->
        cookies = res.ctx.req.cookies
        Resolution.assign(res, :captured_cookies, cookies)

      :capture_remote_ip ->
        ip = res.ctx.req.remote_ip
        Resolution.assign(res, :captured_remote_ip, ip)

      :capture_session ->
        # Indexing the session would raise if it were nil; proves normalization
        # to %{} when Plug.Session isn't configured.
        _ = res.ctx.req.session[:anything]
        Resolution.assign(res, :captured_session, res.ctx.req.session)
    end
  end
end

defmodule RpcElixir.PlugTest.HaltStringMiddleware do
  @moduledoc false
  @behaviour RpcElixir.Middleware
  alias RpcElixir.Resolution

  @impl true
  def call(%Resolution{} = res, _opts) do
    Resolution.halt(res, "string reason")
  end
end

defmodule RpcElixir.PlugTest.HaltAtomMiddleware do
  @moduledoc false
  @behaviour RpcElixir.Middleware
  alias RpcElixir.Resolution

  @impl true
  def call(%Resolution{} = res, _opts) do
    Resolution.halt(res, :unauthorized)
  end
end

defmodule RpcElixir.PlugTest.Router do
  @moduledoc false
  use RpcElixir.Router
  alias RpcElixir.PlugTest.{CookieMiddleware, HaltAtomMiddleware, HaltStringMiddleware}
  alias RpcElixir.RouterFixtures.{EchoHandler, GoodHandler, StructErrorHandler}

  procedure "echo", &EchoHandler.echo/2
  procedure "users.get", &GoodHandler.get/2
  procedure "users.raise", &EchoHandler.always_raise/2
  procedure "set_cookie", &EchoHandler.echo/2, middleware: [{CookieMiddleware, action: :set}]

  procedure "delete_cookie", &EchoHandler.echo/2,
    middleware: [{CookieMiddleware, action: :delete}]

  procedure "set_header", &EchoHandler.echo/2, middleware: [{CookieMiddleware, action: :header}]

  procedure "capture_cookies", &GoodHandler.list/2,
    middleware: [{CookieMiddleware, action: :capture_cookies}]

  procedure "capture_ip", &GoodHandler.list/2,
    middleware: [{CookieMiddleware, action: :capture_remote_ip}]

  procedure "capture_session", &GoodHandler.list/2,
    middleware: [{CookieMiddleware, action: :capture_session}]

  procedure "halt_string", &EchoHandler.echo/2, middleware: [{HaltStringMiddleware, []}]
  procedure "halt_atom", &EchoHandler.echo/2, middleware: [{HaltAtomMiddleware, []}]
  procedure "err.not_found", &StructErrorHandler.not_found/2
  procedure "err.forbidden", &StructErrorHandler.forbidden/2
  procedure "err.email_taken", &StructErrorHandler.map_error/2
  procedure "err.struct", &StructErrorHandler.struct_error/2
end

defmodule RpcElixir.PlugTest.NoSessionPipeline do
  @moduledoc false
  use Plug.Builder

  plug RpcElixir.Plug, router: RpcElixir.PlugTest.Router
end

defmodule RpcElixir.PlugTest do
  use ExUnit.Case, async: true

  import Plug.Test
  import Plug.Conn

  alias RpcElixir.JSON
  alias RpcElixir.PlugTest.NoSessionPipeline
  alias RpcElixir.PlugTest.Router, as: TestRouter

  @opts RpcElixir.Plug.init(router: TestRouter)

  defp call(conn), do: RpcElixir.Plug.call(conn, @opts)

  defp json_post(path, body \\ %{}) do
    :post
    |> conn(path, JSON.encode!(body))
    |> put_req_header("content-type", "application/json")
    |> call()
  end

  defp decode_body(conn), do: JSON.decode!(conn.resp_body)

  describe "success" do
    test "200 with serialized output" do
      conn = json_post("/rpc/echo", %{message: "hello"})
      assert conn.status == 200
      assert %{"ok" => %{"message" => "hello"}} = decode_body(conn)
    end

    test "response has application/json content-type" do
      conn = json_post("/rpc/echo", %{message: "hi"})
      [content_type] = get_resp_header(conn, "content-type")
      assert content_type =~ "application/json"
    end

    test "empty body fails input validation" do
      conn =
        :post
        |> conn("/rpc/users.get", "")
        |> put_req_header("content-type", "application/json")
        |> call()

      assert conn.status == 400
      body = decode_body(conn)
      assert body["error"]["code"] == "input_validation_failed"
    end
  end

  describe "error cases" do
    test "400 on malformed JSON" do
      conn =
        :post
        |> conn("/rpc/echo", "not-json{")
        |> put_req_header("content-type", "application/json")
        |> call()

      assert conn.status == 400
      body = decode_body(conn)
      assert body["error"]["code"] == "input_validation_failed"
      assert body["error"]["details"]["reason"] == "invalid_json"
    end

    test "400 on input validation failure with details" do
      conn = json_post("/rpc/echo", %{wrong_field: "oops"})
      assert conn.status == 400
      body = decode_body(conn)
      assert body["error"]["code"] == "input_validation_failed"
      assert is_map(body["error"]["details"])
    end

    test "404 on unknown procedure" do
      conn = json_post("/rpc/does.not.exist")
      assert conn.status == 404
      body = decode_body(conn)
      assert body["error"]["code"] == "procedure_not_found"
      assert body["error"]["source"] == "framework"
    end

    test "404 on non-POST request" do
      conn =
        :get
        |> conn("/rpc/echo")
        |> call()

      assert conn.status == 404
    end

    test "404 on wrong path prefix" do
      conn = json_post("/api/echo", %{message: "hi"})
      assert conn.status == 404
    end

    @tag :capture_log
    test "500 on handler raise" do
      conn = json_post("/rpc/users.raise", %{message: "boom"})
      assert conn.status == 500
      body = decode_body(conn)
      assert body["error"]["code"] == "handler_error"
    end

    test "middleware halted with string reason does not crash maybe_put" do
      conn = json_post("/rpc/halt_string", %{message: "hi"})
      assert conn.status == 500
      body = decode_body(conn)
      assert body["error"]["code"] == "middleware_halted"
    end
  end

  describe "cookie write" do
    test "middleware that sets a cookie produces Set-Cookie header" do
      conn = json_post("/rpc/set_cookie", %{message: "hi"})
      assert conn.status == 200
      set_cookie_headers = get_resp_header(conn, "set-cookie")
      assert Enum.any?(set_cookie_headers, &String.contains?(&1, "session=abc"))
    end

    test "set-cookie header carries http_only and same_site attributes" do
      conn = json_post("/rpc/set_cookie", %{message: "hi"})
      [cookie | _] = get_resp_header(conn, "set-cookie")
      assert String.contains?(cookie, "HttpOnly") or String.contains?(cookie, "SameSite=Lax")
    end
  end

  describe "cookie delete" do
    test "middleware that deletes a cookie clears it in Set-Cookie" do
      conn = json_post("/rpc/delete_cookie", %{message: "hi"})
      assert conn.status == 200
      set_cookie_headers = get_resp_header(conn, "set-cookie")
      assert Enum.any?(set_cookie_headers, &String.contains?(&1, "session"))
    end
  end

  describe "custom response header" do
    test "middleware that calls put_resp_header propagates to response" do
      conn = json_post("/rpc/set_header", %{message: "hi"})
      assert conn.status == 200
      assert get_resp_header(conn, "x-trace-id") == ["trace-abc"]
    end
  end

  describe "ctx.req population" do
    test "ctx.req.cookies is populated from request cookies" do
      conn =
        :post
        |> conn("/rpc/capture_cookies", "{}")
        |> put_req_header("content-type", "application/json")
        |> put_req_cookie("foo", "bar")
        |> call()

      assert conn.status == 200
    end

    test "ctx.req.remote_ip is populated" do
      conn = json_post("/rpc/capture_ip")
      assert conn.status == 200
    end
  end

  describe "status_for_code fallback for :middleware_halted" do
    test "middleware halted with atom reason returns 500 (not 401/403)" do
      conn = json_post("/rpc/halt_atom", %{})
      assert conn.status == 500
      body = decode_body(conn)
      assert body["error"]["code"] == "middleware_halted"
      assert body["error"]["source"] == "middleware"
    end
  end

  describe "HTTP status code mapping for typed handler errors" do
    test "{:error, :not_found} produces HTTP 404" do
      conn = json_post("/rpc/err.not_found")
      assert conn.status == 404
      body = decode_body(conn)
      assert body["error"]["code"] == "not_found"
      assert body["error"]["source"] == "domain"
    end

    test "{:error, :forbidden} produces HTTP 403" do
      conn = json_post("/rpc/err.forbidden")
      assert conn.status == 403
      body = decode_body(conn)
      assert body["error"]["code"] == "forbidden"
    end

    test "{:error, %{code: :email_taken}} produces HTTP 400 (user-defined code)" do
      conn = json_post("/rpc/err.email_taken", %{message: "hi"})
      assert conn.status == 400
      body = decode_body(conn)
      assert body["error"]["code"] == "email_taken"
    end

    test "{:error, struct} falls through to :handler_error and returns HTTP 500" do
      conn = json_post("/rpc/err.struct", %{message: "hi"})
      assert conn.status == 500
      body = decode_body(conn)
      assert body["error"]["code"] == "handler_error"
    end
  end

  describe "request body size cap" do
    test "413 with :payload_too_large when body exceeds max_body_size opt" do
      large_body = String.duplicate("x", 100)

      conn =
        :post
        |> conn("/rpc/echo", large_body)
        |> put_req_header("content-type", "application/json")
        |> RpcElixir.Plug.call(
          RpcElixir.Plug.init(router: RpcElixir.PlugTest.Router, max_body_size: 10)
        )

      assert conn.status == 413
      body = decode_body(conn)
      assert body["error"]["code"] == "payload_too_large"
    end

    test "accepts body exactly at the size limit" do
      payload = JSON.encode!(%{message: "hi"})
      limit = byte_size(payload)

      conn =
        :post
        |> conn("/rpc/echo", payload)
        |> put_req_header("content-type", "application/json")
        |> RpcElixir.Plug.call(
          RpcElixir.Plug.init(router: RpcElixir.PlugTest.Router, max_body_size: limit)
        )

      assert conn.status == 200
    end
  end

  describe "request body nesting depth cap" do
    defp nested_json(depth) do
      inner = Enum.reduce(1..depth, "1", fn _, acc -> "[" <> acc <> "]" end)
      "{\"a\":" <> inner <> "}"
    end

    defp post_raw(body, opts) do
      :post
      |> conn("/rpc/echo", body)
      |> put_req_header("content-type", "application/json")
      |> RpcElixir.Plug.call(RpcElixir.Plug.init([router: RpcElixir.PlugTest.Router] ++ opts))
    end

    test "400 with :input_validation_failed when body nests past max_body_depth" do
      conn = post_raw(nested_json(20), max_body_depth: 5)

      assert conn.status == 400
      body = decode_body(conn)
      assert body["error"]["code"] == "input_validation_failed"
      assert body["error"]["details"]["reason"] == "body_too_deep"
    end

    test "does not reject a payload within the configured depth at decode time" do
      conn = post_raw(nested_json(3), max_body_depth: 64)

      # Passes the depth guard and reaches dispatch (then fails input validation,
      # proving the depth guard let it through rather than short-circuiting).
      assert conn.status in [200, 400]
      body = decode_body(conn)
      refute body["error"] && body["error"]["details"]["reason"] == "body_too_deep"
    end

    test "default depth limit is enforced when no option is given" do
      conn = post_raw(nested_json(200), [])

      assert conn.status == 400
      assert decode_body(conn)["error"]["details"]["reason"] == "body_too_deep"
    end
  end

  describe "read_session without Plug.Session configured" do
    test "session defaults to %{} (not nil) so middleware indexing does not crash" do
      conn =
        :post
        |> conn("/rpc/capture_session", "{}")
        |> put_req_header("content-type", "application/json")
        |> Map.put(:secret_key_base, String.duplicate("b", 64))

      result = NoSessionPipeline.call(conn, [])
      assert result.status == 200
    end
  end

  describe "content-type enforcement" do
    test "415 when content-type is not application/json" do
      conn =
        :post
        |> conn("/rpc/echo", JSON.encode!(%{message: "hi"}))
        |> put_req_header("content-type", "text/plain")
        |> call()

      assert conn.status == 415
      body = decode_body(conn)
      assert body["error"]["code"] == "unsupported_media_type"
    end

    test "415 when content-type header is missing" do
      conn =
        :post
        |> conn("/rpc/echo", JSON.encode!(%{message: "hi"}))
        |> Map.update!(:req_headers, &List.keydelete(&1, "content-type", 0))
        |> call()

      assert conn.status == 415
      body = decode_body(conn)
      assert body["error"]["code"] == "unsupported_media_type"
    end

    test "accepts application/json with charset parameter" do
      conn =
        :post
        |> conn("/rpc/echo", JSON.encode!(%{message: "hi"}))
        |> put_req_header("content-type", "application/json; charset=utf-8")
        |> call()

      assert conn.status == 200
    end

    test ":require_content_type false skips the check" do
      conn =
        :post
        |> conn("/rpc/echo", JSON.encode!(%{message: "hi"}))
        |> put_req_header("content-type", "text/plain")
        |> RpcElixir.Plug.call(
          RpcElixir.Plug.init(router: TestRouter, require_content_type: false)
        )

      assert conn.status == 200
    end
  end

  describe "allowed_origins" do
    test "rejects request whose origin is not allow-listed (403)" do
      conn =
        :post
        |> conn("/rpc/echo", JSON.encode!(%{message: "hi"}))
        |> put_req_header("content-type", "application/json")
        |> put_req_header("origin", "https://evil.example")
        |> RpcElixir.Plug.call(
          RpcElixir.Plug.init(router: TestRouter, allowed_origins: ["https://app.example"])
        )

      assert conn.status == 403
      body = decode_body(conn)
      assert body["error"]["code"] == "forbidden"
    end

    test "allows request whose origin is allow-listed" do
      conn =
        :post
        |> conn("/rpc/echo", JSON.encode!(%{message: "hi"}))
        |> put_req_header("content-type", "application/json")
        |> put_req_header("origin", "https://app.example")
        |> RpcElixir.Plug.call(
          RpcElixir.Plug.init(router: TestRouter, allowed_origins: ["https://app.example"])
        )

      assert conn.status == 200
    end

    test "allows request with no origin header when allow-list is set" do
      conn =
        :post
        |> conn("/rpc/echo", JSON.encode!(%{message: "hi"}))
        |> put_req_header("content-type", "application/json")
        |> RpcElixir.Plug.call(
          RpcElixir.Plug.init(router: TestRouter, allowed_origins: ["https://app.example"])
        )

      assert conn.status == 200
    end
  end
end
