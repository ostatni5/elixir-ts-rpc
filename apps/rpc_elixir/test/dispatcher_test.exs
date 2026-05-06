defmodule RpcElixir.DispatcherTest.Router do
  use RpcElixir.Router
  alias RpcElixir.RouterFixtures.{EchoHandler, GoodHandler, StructErrorHandler}

  procedure "query.echo", &EchoHandler.echo/2
  procedure "mutation.fail", &EchoHandler.fail/2
  procedure "mutation.bad_output", &EchoHandler.bad_output/2
  procedure "mutation.raise", &EchoHandler.always_raise/2
  procedure "mutation.rpc_error", &EchoHandler.rpc_error/2
  procedure "users.get", &GoodHandler.get/2
  procedure "users.update", &GoodHandler.update/2
  procedure "mutation.map_error", &StructErrorHandler.map_error/2
  procedure "mutation.struct_error", &StructErrorHandler.struct_error/2
end

defmodule RpcElixir.DispatcherTest.UnixMillisRouter do
  use RpcElixir.Router, wire_aliases: [{DateTime, RpcElixir.UnixMillis}]
  alias RpcElixir.CodegenFixtures.UnixMillisInputHandlers
  procedure "instant.echo", &UnixMillisInputHandlers.call/2
end

defmodule RpcElixir.DispatcherTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias RpcElixir.{Context, Dispatcher, Resolution, RpcError}
  alias RpcElixir.DispatcherTest.Router, as: DispatcherRouter

  defp resolution(path), do: %Resolution{procedure: path}

  defp dispatch(path, input, res \\ nil) do
    res = res || resolution(path)
    Dispatcher.dispatch(DispatcherRouter, path, input, res)
  end

  defp result(path, input, res \\ nil), do: dispatch(path, input, res).result

  describe "happy path" do
    test "valid input returns serialized output on resolution" do
      res = dispatch("query.echo", %{"message" => "hello"})
      assert res.state == :continue
      assert {:ok, %{message: "hello"}} = res.result
    end

    test "query procedure dispatches correctly" do
      assert {:ok, %{id: _, email: _}} = result("users.get", %{"id" => "1"})
    end

    test "mutation procedure dispatches correctly" do
      assert {:ok, %{id: _}} =
               result("users.update", %{"id" => "1", "email" => "x@example.com"})
    end

    test "ctx is threaded through to the handler" do
      ctx = %Context{assigns: %{user_id: "42"}}
      res = %Resolution{procedure: "query.echo", ctx: ctx}

      assert {:ok, %{message: "hi"}} = result("query.echo", %{"message" => "hi"}, res)
    end
  end

  describe "procedure not found" do
    test "unknown path returns :procedure_not_found error" do
      assert {:error, %RpcError{code: :procedure_not_found, source: :framework}} =
               result("no.such.proc", %{})
    end

    test "error message references the missing path" do
      {:error, %RpcError{message: msg}} = result("ghost", %{})
      assert msg =~ "ghost"
    end
  end

  describe "input validation failure" do
    test "wrong type returns :input_validation_failed" do
      assert {:error, %RpcError{code: :input_validation_failed}} =
               result("query.echo", %{"message" => 123})
    end

    test "missing required field returns :input_validation_failed with field details" do
      {:error, %RpcError{code: :input_validation_failed, details: details}} =
        result("query.echo", %{})

      assert is_map(details)
      assert Map.has_key?(details, "message")
    end

    test "unexpected field returns :input_validation_failed with field details" do
      {:error, %RpcError{code: :input_validation_failed, details: details}} =
        result("query.echo", %{"message" => "hi", "extra" => "bad"})

      assert Map.has_key?(details, "extra")
    end
  end

  describe "handler error" do
    test "handler returning {:error, atom} promotes atom to top-level code" do
      assert {:error,
              %RpcError{
                code: :always,
                message: "always",
                details: nil,
                status: nil,
                source: :domain
              }} =
               result("mutation.fail", %{"message" => "hi"})
    end

    @tag :capture_log
    test "handler raising an exception returns :handler_error with kind :exception" do
      {:error, %RpcError{code: :handler_error, details: details}} =
        result("mutation.raise", %{"message" => "hi"})

      assert details.kind == :exception
    end

    @tag :capture_log
    test "handler raising an exception exposes message when :expose_error_details is true" do
      Application.put_env(:elixir_ts_rpc, :expose_error_details, true)

      try do
        {:error, %RpcError{code: :handler_error, details: %{kind: :exception, message: msg}}} =
          result("mutation.raise", %{"message" => "hi"})

        assert is_binary(msg)
      after
        Application.delete_env(:elixir_ts_rpc, :expose_error_details)
      end
    end

    test "handler returning {:error, %{code: atom}} promotes map to typed error without status" do
      assert {:error, %RpcError{code: :email_taken, status: nil, source: :domain}} =
               result("mutation.map_error", %{"message" => "hi"})
    end

    test "handler returning a bare %RpcError{} with nil source defaults to :domain" do
      assert {:error, %RpcError{code: :custom, source: :domain}} =
               result("mutation.rpc_error", %{"message" => "hi"})
    end

    @tag :capture_log
    test "handler raise catch-all is tagged source: :framework" do
      assert {:error, %RpcError{code: :handler_error, source: :framework}} =
               result("mutation.raise", %{"message" => "hi"})
    end

    test "handler returning {:error, struct} falls through to handler_error catch-all" do
      assert {:error, %RpcError{code: :handler_error}} =
               result("mutation.struct_error", %{"message" => "hi"})
    end
  end

  describe "halted resolution" do
    test "returns the halted resolution unchanged without invoking the handler" do
      halted =
        %Resolution{procedure: "mutation.raise"}
        |> Resolution.halt(:auth_required)

      res = dispatch("mutation.raise", %{}, halted)

      assert res.state == :halted

      assert {:error, %RpcError{code: :middleware_halted, details: %{reason: :auth_required}}} =
               res.result
    end
  end

  describe "middleware wrote :result without halting" do
    test "warns and clobbers the pre-set :result with the handler output" do
      res = %Resolution{procedure: "query.echo", result: {:ok, %{message: "stale"}}}

      log =
        capture_log(fn ->
          send(self(), {:dispatched, dispatch("query.echo", %{"message" => "fresh"}, res)})
        end)

      assert_received {:dispatched, dispatched}
      assert log =~ "without halting"
      assert {:ok, %{message: "fresh"}} = dispatched.result
    end

    test "halting is the supported short-circuit mechanism and emits no warning" do
      halted =
        %Resolution{procedure: "query.echo"}
        |> Resolution.halt(%RpcError{code: :short_circuit, message: "stop"})

      log =
        capture_log(fn ->
          send(self(), {:dispatched, dispatch("query.echo", %{"message" => "fresh"}, halted)})
        end)

      assert_received {:dispatched, dispatched}
      refute log =~ "without halting"
      assert {:error, %RpcError{code: :short_circuit}} = dispatched.result
    end
  end

  describe "output validation failure" do
    test "handler returning wrong output shape returns :output_validation_failed" do
      assert {:error, %RpcError{code: :output_validation_failed, source: :framework}} =
               result("mutation.bad_output", %{"message" => "hi"})
    end

    test "output validation error is distinct from input validation error" do
      {:error, %RpcError{code: output_code}} = result("mutation.bad_output", %{"message" => "hi"})
      {:error, %RpcError{code: input_code}} = result("query.echo", %{})

      assert output_code == :output_validation_failed
      assert input_code == :input_validation_failed
    end
  end

  describe "custom-type input deserialization at request time" do
    alias RpcElixir.DispatcherTest.UnixMillisRouter

    test "an integer wire value for a UnixMillis-aliased field is decoded to a DateTime before the handler" do
      ms = 1_700_000_000_123
      Process.put(:received_input_sink, self())

      result =
        Dispatcher.dispatch(
          UnixMillisRouter,
          "instant.echo",
          %{"at" => ms},
          %Resolution{procedure: "instant.echo"}
        ).result

      assert {:ok, _} = result

      assert_received {:handler_received, %DateTime{} = received}
      assert DateTime.to_unix(received, :millisecond) == ms
    end
  end

  describe "in-process call/4 helper" do
    test "produces same result as dispatch on happy path" do
      dispatch_result =
        Dispatcher.dispatch(
          DispatcherRouter,
          "query.echo",
          %{"message" => "hello"},
          resolution("query.echo")
        ).result

      call_result = RpcElixir.call(DispatcherRouter, "query.echo", %{"message" => "hello"})

      assert dispatch_result == call_result
    end

    test "produces :procedure_not_found on unknown path" do
      assert {:error, %RpcError{code: :procedure_not_found}} =
               RpcElixir.call(DispatcherRouter, "nope", %{})
    end

    test "produces :input_validation_failed on bad input" do
      assert {:error, %RpcError{code: :input_validation_failed}} =
               RpcElixir.call(DispatcherRouter, "query.echo", %{"message" => 0})
    end

    test "accepts a %Context{} as ctx" do
      ctx = %Context{assigns: %{user: "alice"}}

      assert {:ok, _} =
               RpcElixir.call(DispatcherRouter, "query.echo", %{"message" => "hi"}, ctx)
    end

    test "default ctx argument works" do
      assert {:ok, %{message: "hi"}} =
               RpcElixir.call(DispatcherRouter, "query.echo", %{"message" => "hi"})
    end
  end
end
