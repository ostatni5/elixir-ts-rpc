defmodule RpcElixir.MiddlewareTest.AssignRouter do
  use RpcElixir.Router

  alias RpcElixir.Middleware.Assign
  alias RpcElixir.RouterFixtures.EchoHandler

  procedure "echo.plain", &EchoHandler.echo/2

  procedure "echo.assigned", &EchoHandler.echo/2, middleware: [{Assign, source: :api, env: :test}]

  procedure "echo.bare", &EchoHandler.echo/2, middleware: [Assign]
end

defmodule RpcElixir.MiddlewareTest.HaltRouter do
  use RpcElixir.Router

  alias RpcElixir.RouterFixtures.{EchoHandler, HaltingMiddleware, TraceMiddleware}

  procedure "echo.halted", &EchoHandler.echo/2,
    middleware: [
      {TraceMiddleware, tag: :before_halt},
      {HaltingMiddleware, reason: :nope},
      {TraceMiddleware, tag: :after_halt}
    ]

  procedure "echo.traced", &EchoHandler.echo/2,
    middleware: [
      {TraceMiddleware, tag: :first},
      {TraceMiddleware, tag: :second}
    ]
end

defmodule RpcElixir.MiddlewareTest do
  use ExUnit.Case, async: true

  alias RpcElixir.{Dispatcher, Resolution}
  alias RpcElixir.MiddlewareTest.{AssignRouter, HaltRouter}

  defp dispatch(router, path, input \\ %{"message" => "hi"}) do
    Dispatcher.dispatch(router, path, input, %Resolution{procedure: path})
  end

  describe "Assign built-in" do
    test "puts opts pairs into ctx.assigns" do
      res = dispatch(AssignRouter, "echo.assigned")

      assert res.ctx.assigns.source == :api
      assert res.ctx.assigns.env == :test
      assert {:ok, %{message: "hi"}} = res.result
    end

    test "bare-module form is a no-op" do
      res = dispatch(AssignRouter, "echo.bare")
      assert res.ctx.assigns == %{}
    end

    test "no middleware leaves ctx.assigns untouched" do
      res = dispatch(AssignRouter, "echo.plain")
      assert res.ctx.assigns == %{}
    end
  end

  describe "halt short-circuits" do
    test "halt stops downstream middleware and the handler" do
      res = dispatch(HaltRouter, "echo.halted")

      assert res.state == :halted

      assert {:error, %RpcElixir.RpcError{code: :middleware_halted, details: %{reason: :nope}}} =
               res.result

      assert res.private[:trace] == [:before_halt]
    end

    test "non-halting chain runs in order then dispatches handler" do
      res = dispatch(HaltRouter, "echo.traced")

      assert res.state == :continue
      assert res.private[:trace] == [:first, :second]
      assert {:ok, %{message: "hi"}} = res.result
    end
  end

  describe "compile-time validation" do
    test "non-list middleware raises CompileError" do
      assert_raise CompileError, ~r/middleware must be a list/, fn ->
        Code.eval_string("""
        defmodule RpcElixir.MiddlewareTest.BadList do
          use RpcElixir.Router
          alias RpcElixir.RouterFixtures.EchoHandler
          procedure "x", &EchoHandler.echo/2, middleware: :nope
        end
        """)
      end
    end

    test "non-module entry raises CompileError" do
      assert_raise CompileError, ~r/middleware entry must be a module/, fn ->
        Code.eval_string("""
        defmodule RpcElixir.MiddlewareTest.BadEntry do
          use RpcElixir.Router
          alias RpcElixir.RouterFixtures.EchoHandler
          procedure "x", &EchoHandler.echo/2, middleware: ["not-a-mod"]
        end
        """)
      end
    end

    test "module without call/2 raises CompileError" do
      assert_raise CompileError, ~r/must export call\/2/, fn ->
        Code.eval_string("""
        defmodule RpcElixir.MiddlewareTest.NoCall do
          def hello, do: :world
        end

        defmodule RpcElixir.MiddlewareTest.BadCallable do
          use RpcElixir.Router
          alias RpcElixir.RouterFixtures.EchoHandler
          procedure "x", &EchoHandler.echo/2,
            middleware: [RpcElixir.MiddlewareTest.NoCall]
        end
        """)
      end
    end
  end
end
