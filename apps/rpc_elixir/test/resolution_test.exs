defmodule RpcElixir.ResolutionTest do
  use ExUnit.Case, async: true

  alias RpcElixir.{Context, Resolution, RpcError}

  describe "defaults" do
    test "fresh resolution has state :continue" do
      assert %Resolution{state: :continue} = %Resolution{procedure: "test"}
    end

    test "fresh resolution has empty params and private" do
      res = %Resolution{procedure: "test"}
      assert res.params == %{}
      assert res.private == %{}
      assert res.result == nil
      assert res.procedure == "test"
    end

    test "context struct defaults all nil or empty maps" do
      ctx = %Context{}
      assert ctx.conn == nil
      assert ctx.socket == nil
      assert ctx.assigns == %{}
      assert ctx.private == %{}
    end
  end

  describe "halt/2" do
    test "wraps a non-RpcError reason in a :middleware_halted RpcError" do
      res = Resolution.halt(%Resolution{procedure: "test"}, :unauthorized)
      assert res.state == :halted

      assert {:error, %RpcError{code: :middleware_halted, details: %{reason: :unauthorized}}} =
               res.result
    end

    test "passes through a fully-formed %RpcError{}, defaulting source to :middleware" do
      err = %RpcError{code: :unauthenticated, message: "no session", details: %{}}
      res = Resolution.halt(%Resolution{procedure: "test"}, err)

      assert res.state == :halted
      assert res.result == {:error, %{err | source: :middleware}}
    end

    test "preserves an explicit source on a fully-formed %RpcError{}" do
      err = %RpcError{code: :teapot, message: "brewing", source: :domain}
      res = Resolution.halt(%Resolution{procedure: "test"}, err)

      assert {:error, %RpcError{source: :domain}} = res.result
    end

    test "tags a wrapped middleware halt with source: :middleware" do
      res = Resolution.halt(%Resolution{procedure: "test"}, :unauthorized)
      assert {:error, %RpcError{code: :middleware_halted, source: :middleware}} = res.result
    end

    test "calling halt/2 twice overwrites the result with the second reason" do
      res =
        %Resolution{procedure: "test"}
        |> Resolution.halt(:first)
        |> Resolution.halt(:second)

      assert res.state == :halted
      assert {:error, %RpcError{details: %{reason: :second}}} = res.result
    end
  end

  describe "put_ctx/3" do
    test "updates a known field on the nested ctx struct" do
      conn = %{method: "POST"}
      res = Resolution.put_ctx(%Resolution{procedure: "test"}, :conn, conn)
      assert res.ctx.conn == conn
    end

    test "raises KeyError for fields not defined on %Context{}" do
      assert_raise KeyError, fn ->
        Resolution.put_ctx(%Resolution{procedure: "test"}, :current_user, %{id: 1})
      end
    end
  end

  describe "put_private/3" do
    test "stores a key in the private map" do
      res = Resolution.put_private(%Resolution{procedure: "test"}, :trace_id, "abc123")
      assert res.private.trace_id == "abc123"
    end
  end

  describe "assign/3" do
    test "stores a key in ctx.assigns" do
      res = Resolution.assign(%Resolution{procedure: "test"}, :locale, "en")
      assert res.ctx.assigns.locale == "en"
    end
  end

  describe "put_resp_cookie/4" do
    test "stores cookie entry with value and opts" do
      res =
        Resolution.put_resp_cookie(%Resolution{procedure: "test"}, "session", "tok",
          http_only: true
        )

      assert res.resp_cookies["session"] == {"tok", [http_only: true]}
    end

    test "defaults to empty opts" do
      res = Resolution.put_resp_cookie(%Resolution{procedure: "test"}, "session", "tok")
      assert res.resp_cookies["session"] == {"tok", []}
    end

    test "overwrites existing cookie with same name" do
      res =
        %Resolution{procedure: "test"}
        |> Resolution.put_resp_cookie("session", "first")
        |> Resolution.put_resp_cookie("session", "second")

      assert res.resp_cookies["session"] == {"second", []}
    end
  end

  describe "delete_resp_cookie/3" do
    test "stores :delete entry for the cookie name" do
      res = Resolution.delete_resp_cookie(%Resolution{procedure: "test"}, "session")
      assert res.resp_cookies["session"] == {:delete, []}
    end

    test "supports opts forwarded to adapter" do
      res = Resolution.delete_resp_cookie(%Resolution{procedure: "test"}, "session", path: "/")
      assert res.resp_cookies["session"] == {:delete, [path: "/"]}
    end
  end

  describe "clear_session/1" do
    test "sets resp_session_clear to true and leaves resp_session empty" do
      res = %Resolution{procedure: "test"}
      cleared = Resolution.clear_session(res)
      assert cleared.resp_session_clear == true
      assert cleared.resp_session == %{}
    end

    test "clear is not reachable by put_session with :__clear__ key" do
      res = %Resolution{procedure: "test"}
      sentinel = Resolution.put_session(res, :__clear__, true)
      assert sentinel.resp_session_clear == false
      assert sentinel.resp_session == %{__clear__: true}
    end
  end

  describe "put_resp_header/3" do
    test "appends a header to resp_headers" do
      res = Resolution.put_resp_header(%Resolution{procedure: "test"}, "x-foo", "bar")
      assert res.resp_headers == [{"x-foo", "bar"}]
    end

    test "allows duplicate header names" do
      res =
        %Resolution{procedure: "test"}
        |> Resolution.put_resp_header("x-foo", "first")
        |> Resolution.put_resp_header("x-foo", "second")

      assert res.resp_headers == [{"x-foo", "first"}, {"x-foo", "second"}]
    end

    test "fresh resolution has empty resp_headers" do
      assert %Resolution{procedure: "test"}.resp_headers == []
    end

    test "fresh resolution has empty resp_cookies" do
      assert %Resolution{procedure: "test"}.resp_cookies == %{}
    end
  end
end
