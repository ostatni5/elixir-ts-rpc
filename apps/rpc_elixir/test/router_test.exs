defmodule RpcElixir.RouterTest.SingleProcedureRouter do
  use RpcElixir.Router
  alias RpcElixir.RouterFixtures.GoodHandler
  procedure "users.get", &GoodHandler.get/2
end

defmodule RpcElixir.RouterTest.MiddlewareRouter do
  use RpcElixir.Router
  alias RpcElixir.Middleware.Assign
  alias RpcElixir.RouterFixtures.GoodHandler
  procedure "users.update", &GoodHandler.update/2, middleware: [Assign, {Assign, opt: 1}]
end

defmodule RpcElixir.RouterTest.EmptyRouter do
  use RpcElixir.Router
end

defmodule RpcElixir.RouterTest.WireAliasRouter do
  use RpcElixir.Router, wire_aliases: [{DateTime, RpcElixir.UnixMillis}]
  alias RpcElixir.ManifestFixtures.Handlers
  procedure "users.create", &Handlers.create_user/2
end

defmodule RpcElixir.RouterTest.NoAliasRouter do
  use RpcElixir.Router
  alias RpcElixir.ManifestFixtures.Handlers
  procedure "users.create", &Handlers.create_user/2
end

defmodule RpcElixir.RouterTest.EctoWireAliasRouter do
  use RpcElixir.Router, wire_aliases: [{DateTime, RpcElixir.UnixMillis}]
  alias RpcElixir.CodegenFixtures.EctoTimestampHandlers
  procedure "ecto.call", &EctoTimestampHandlers.call/2
end

defmodule RpcElixir.RouterTest.EctoNoAliasRouter do
  use RpcElixir.Router
  alias RpcElixir.CodegenFixtures.EctoTimestampHandlers
  procedure "ecto.call", &EctoTimestampHandlers.call/2
end

defmodule RpcElixir.RouterTest.WrappedAliasRouter do
  use RpcElixir.Router, wire_aliases: [{DateTime, RpcElixir.UnixMillis}]
  alias RpcElixir.CodegenFixtures.WrappedDateTimeHandlers
  procedure "wrapped.call", &WrappedDateTimeHandlers.call/2
end

defmodule RpcElixir.RouterTest.MultiAliasRouter do
  use RpcElixir.Router,
    wire_aliases: [{DateTime, RpcElixir.UnixMillis}, {Date, RpcElixir.TypespecFixtures.Sku}]

  alias RpcElixir.CodegenFixtures.MultiAliasHandlers
  procedure "multi.call", &MultiAliasHandlers.call/2
end

defmodule RpcElixir.RouterTest.MultiProcedureRouter do
  use RpcElixir.Router
  alias RpcElixir.RouterFixtures.GoodHandler
  procedure "users.get", &GoodHandler.get/2
  procedure "users.list", &GoodHandler.list/2
  procedure "users.update", &GoodHandler.update/2
end

defmodule RpcElixir.RouterTest.ErrorSpecRouter do
  use RpcElixir.Router
  alias RpcElixir.RouterFixtures.GoodHandler
  procedure "users.get", &GoodHandler.get/2
  procedure "users.list", &GoodHandler.list/2
end

defmodule RpcElixir.RouterTest.ScopeMiddlewareRouter do
  use RpcElixir.Router
  alias RpcElixir.Middleware.Assign
  alias RpcElixir.RouterFixtures.GoodHandler

  scope middleware: [Assign] do
    procedure "users.get", &GoodHandler.get/2
    procedure "users.update", &GoodHandler.update/2, middleware: [{Assign, opt: 1}]
  end

  procedure "users.list", &GoodHandler.list/2
end

defmodule RpcElixir.RouterTest.ScopePrefixRouter do
  use RpcElixir.Router
  alias RpcElixir.Middleware.Assign
  alias RpcElixir.RouterFixtures.GoodHandler

  scope "users", middleware: [Assign] do
    procedure "get", &GoodHandler.get/2
    procedure "list", &GoodHandler.list/2
  end
end

defmodule RpcElixir.RouterTest.NestedScopeRouter do
  use RpcElixir.Router
  alias RpcElixir.Middleware.Assign
  alias RpcElixir.RouterFixtures.{GoodHandler, TraceMiddleware}

  scope "admin", middleware: [Assign] do
    scope "users", middleware: [{TraceMiddleware, tag: :inner}] do
      procedure "get", &GoodHandler.get/2, middleware: [{Assign, own: true}]
    end
  end
end

defmodule RpcElixir.RouterTest.ExposeRouter do
  use RpcElixir.Router
  alias RpcElixir.RouterFixtures.ExposableHandler

  expose ExposableHandler
end

defmodule RpcElixir.RouterTest.ScopedExposeRouter do
  use RpcElixir.Router
  alias RpcElixir.Middleware.Assign
  alias RpcElixir.RouterFixtures.ExposableHandler

  scope "users", middleware: [Assign] do
    expose ExposableHandler
  end
end

defmodule RpcElixir.RouterTest.MalformedSpecHandler do
  @moduledoc false
  def weird(input, _ctx), do: {:ok, input}

  # A spec AST that is neither `fun(args) :: return` nor a `:when`-bounded variant.
  def __rpc_specs__ do
    %{{:weird, 2} => quote(do: {:ok, integer()})}
  end
end

defmodule RpcElixir.RouterTest do
  use ExUnit.Case, async: true

  alias RpcElixir.RouterFixtures.GoodHandler
  alias RpcElixir.RouterTest.{EmptyRouter, ErrorSpecRouter, MiddlewareRouter}
  alias RpcElixir.RouterTest.{ExposeRouter, ScopedExposeRouter}
  alias RpcElixir.RouterTest.{MultiProcedureRouter, SingleProcedureRouter}
  alias RpcElixir.RouterTest.{NestedScopeRouter, ScopeMiddlewareRouter, ScopePrefixRouter}

  describe "happy path" do
    test "single procedure is registered with expected fields" do
      procedures = SingleProcedureRouter.__procedures__()
      assert length(procedures) == 1

      [proc] = procedures
      assert proc[:name] == "users.get"
      assert proc[:handler_mod] == GoodHandler
      assert proc[:handler_fun] == :get
      assert proc[:doc] == "Fetch a user by id."
      assert proc[:schema_base] == "RpcElixir.RouterFixtures.GoodHandler.get"
      assert proc[:middleware] == []

      assert %{kind: _} = proc[:input]
      assert %{kind: _} = proc[:output]
      assert %{kind: _} = proc[:error]
    end

    test "middleware is normalized to {module, opts} tuples" do
      alias RpcElixir.Middleware.Assign
      [proc] = MiddlewareRouter.__procedures__()
      assert proc[:middleware] == [{Assign, []}, {Assign, opt: 1}]
    end

    test "__manifest__/0 excludes :middleware key but retains all others" do
      manifest = MiddlewareRouter.__manifest__()
      assert length(manifest) == 1

      [entry] = manifest
      refute Map.has_key?(entry, :middleware)
      assert Map.has_key?(entry, :name)
      assert Map.has_key?(entry, :handler_mod)
      assert Map.has_key?(entry, :handler_fun)
      assert Map.has_key?(entry, :input)
      assert Map.has_key?(entry, :output)
      assert Map.has_key?(entry, :doc)
      assert Map.has_key?(entry, :schema_base)
      assert Map.has_key?(entry, :error)
    end

    test ":doc is nil when handler function has no @doc" do
      procedures = MultiProcedureRouter.__procedures__()
      list_proc = Enum.find(procedures, &(&1[:name] == "users.list"))
      assert list_proc[:doc] == nil
    end

    test "empty router returns empty lists" do
      assert EmptyRouter.__procedures__() == []
      assert EmptyRouter.__manifest__() == []
      assert EmptyRouter.__procedures_index__() == %{}
    end

    test "__procedures_index__/0 maps each name to its procedure" do
      index = MultiProcedureRouter.__procedures_index__()
      procedures = MultiProcedureRouter.__procedures__()

      assert map_size(index) == length(procedures)
      assert Map.keys(index) |> Enum.sort() == ["users.get", "users.list", "users.update"]

      for proc <- procedures do
        assert index[proc.name] == proc
      end
    end

    test "multiple procedures are registered in definition order" do
      procedures = MultiProcedureRouter.__procedures__()
      assert length(procedures) == 3
      assert Enum.map(procedures, & &1[:name]) == ["users.get", "users.list", "users.update"]
    end

    test ":error is non-nil for handler with error variant and nil for handler without" do
      procedures = ErrorSpecRouter.__procedures__()
      get_proc = Enum.find(procedures, &(&1[:name] == "users.get"))
      list_proc = Enum.find(procedures, &(&1[:name] == "users.list"))

      assert %{kind: _} = get_proc[:error]
      assert list_proc[:error] == nil
    end
  end

  describe "scope" do
    alias RpcElixir.Middleware.Assign
    alias RpcElixir.RouterFixtures.TraceMiddleware

    test "scope middleware is prepended to procedures inside the block" do
      proc = index(ScopeMiddlewareRouter)["users.get"]
      assert proc.middleware == [{Assign, []}]
    end

    test "scope middleware runs before procedure-specific middleware" do
      proc = index(ScopeMiddlewareRouter)["users.update"]
      assert proc.middleware == [{Assign, []}, {Assign, opt: 1}]
    end

    test "procedures outside any scope are unaffected" do
      proc = index(ScopeMiddlewareRouter)["users.list"]
      assert proc.middleware == []
    end

    test "string prefix is prepended to inner procedure wire names" do
      names = ScopePrefixRouter.__procedures__() |> Enum.map(& &1.name) |> Enum.sort()
      assert names == ["users.get", "users.list"]
    end

    test "nested scopes concatenate prefixes and accumulate middleware outer-to-inner" do
      proc = index(NestedScopeRouter)["admin.users.get"]
      assert proc.name == "admin.users.get"

      assert proc.middleware == [
               {Assign, []},
               {TraceMiddleware, tag: :inner},
               {Assign, own: true}
             ]
    end

    test "raises CompileError on an unknown scope option" do
      assert_raise CompileError, ~r/unknown scope option/i, fn ->
        Code.eval_string("""
        defmodule BadScopeRouter1 do
          use RpcElixir.Router
          alias RpcElixir.RouterFixtures.GoodHandler
          scope "users", middlewares: [] do
            procedure "get", &GoodHandler.get/2
          end
        end
        """)
      end
    end

    test "raises CompileError on an empty-string prefix" do
      assert_raise CompileError, ~r/non-empty string/i, fn ->
        Code.eval_string("""
        defmodule BadScopeRouter2 do
          use RpcElixir.Router
          alias RpcElixir.RouterFixtures.GoodHandler
          scope "", middleware: [] do
            procedure "get", &GoodHandler.get/2
          end
        end
        """)
      end
    end

    test "raises CompileError when a scope middleware module is not middleware" do
      assert_raise CompileError, ~r/@behaviour RpcElixir.Middleware|must export call\/2/i, fn ->
        Code.eval_string("""
        defmodule BadScopeRouter3 do
          use RpcElixir.Router
          alias RpcElixir.RouterFixtures.GoodHandler
          scope middleware: [String] do
            procedure "get", &GoodHandler.get/2
          end
        end
        """)
      end
    end

    defp index(router), do: router.__procedures_index__()
  end

  describe "expose" do
    alias RpcElixir.RouterFixtures.ExposableHandler

    test "registers every public arity-2 @spec'd function, sorted by name" do
      names = ExposeRouter.__procedures__() |> Enum.map(& &1.name)
      assert names == ["get", "list"]
    end

    test "excludes public functions that are not arity 2" do
      names = ExposeRouter.__procedures__() |> Enum.map(& &1.name)
      refute "ping" in names
    end

    test "exposed procedures point at the source module and function" do
      proc = ExposeRouter.__procedures_index__()["get"]
      assert proc.handler_mod == ExposableHandler
      assert proc.handler_fun == :get
      assert %{kind: _} = proc.input
      assert %{kind: _} = proc.output
    end

    test "composes with an enclosing scope's prefix and middleware" do
      alias RpcElixir.Middleware.Assign
      index = ScopedExposeRouter.__procedures_index__()

      assert Enum.sort(Map.keys(index)) == ["users.get", "users.list"]
      assert index["users.get"].middleware == [{Assign, []}]
      assert index["users.list"].middleware == [{Assign, []}]
    end

    test "raises CompileError when the module does not use RpcElixir.Handler" do
      assert_raise CompileError, ~r/requires `use RpcElixir.Handler`/, fn ->
        Code.eval_string("""
        defmodule BadExposeRouter1 do
          use RpcElixir.Router
          alias RpcElixir.RouterFixtures.GoodHandler
          expose GoodHandler
        end
        """)
      end
    end

    test "raises CompileError when the module has no arity-2 functions to expose" do
      assert_raise CompileError, ~r/no public arity-2 @spec'd functions/, fn ->
        Code.eval_string("""
        defmodule BadExposeRouter2 do
          use RpcElixir.Router
          alias RpcElixir.RouterFixtures.ArityOneOnlyHandler
          expose ArityOneOnlyHandler
        end
        """)
      end
    end
  end

  describe "compile errors" do
    test "raises CompileError when capture has wrong arity" do
      assert_raise CompileError, ~r/arity 2/i, fn ->
        Code.eval_string("""
        defmodule BadRouter1 do
          use RpcElixir.Router
          alias RpcElixir.RouterFixtures.GoodHandler
          procedure "users.get", &GoodHandler.get/3
        end
        """)
      end
    end

    test "raises CompileError when given a non-capture value" do
      assert_raise CompileError, ~r/remote function capture|&Mod\.fun/i, fn ->
        Code.eval_string("""
        defmodule BadRouter2 do
          use RpcElixir.Router
          procedure "users.get", :not_a_capture
        end
        """)
      end
    end

    test "raises CompileError when handler function has no @spec" do
      assert_raise CompileError, ~r/no @spec|@spec.*required/i, fn ->
        Code.eval_string("""
        defmodule BadRouter3 do
          use RpcElixir.Router
          alias RpcElixir.RouterFixtures.NoSpecHandler
          procedure "users.get", &NoSpecHandler.get/2
        end
        """)
      end
    end

    test "raises CompileError when handler @spec return has no {:ok, _} variant" do
      assert_raise CompileError, ~r/\{:ok|invalid.*return/i, fn ->
        Code.eval_string("""
        defmodule BadRouter4 do
          use RpcElixir.Router
          alias RpcElixir.RouterFixtures.BadReturnHandler
          procedure "users.get", &BadReturnHandler.get/2
        end
        """)
      end
    end

    test "raises CompileError when handler @spec has an unsupported shape" do
      assert_raise CompileError, ~r/unsupported @spec shape/i, fn ->
        Code.eval_string("""
        defmodule BadRouterSpecShape do
          use RpcElixir.Router
          alias RpcElixir.RouterTest.MalformedSpecHandler
          procedure "weird.call", &MalformedSpecHandler.weird/2
        end
        """)
      end
    end

    test "raises CompileError on duplicate procedure name" do
      assert_raise CompileError, ~r/duplicate|defined more than once|already/i, fn ->
        Code.eval_string("""
        defmodule BadRouter5 do
          use RpcElixir.Router
          alias RpcElixir.RouterFixtures.GoodHandler
          procedure "users.get", &GoodHandler.get/2
          procedure "users.get", &GoodHandler.get/2
        end
        """)
      end
    end

    test "raises CompileError when a wire_aliases target is not a CustomType" do
      assert_raise CompileError, ~r/must implement the RpcElixir.CustomType behaviour/i, fn ->
        Code.eval_string("""
        defmodule BadAliasRouter1 do
          use RpcElixir.Router, wire_aliases: [{DateTime, String}]
        end
        """)
      end
    end

    test "raises CompileError when a wire_aliases source module does not exist" do
      assert_raise CompileError, ~r/source module NotARealModule123 could not be loaded/, fn ->
        Code.eval_string("""
        defmodule BadAliasRouter3 do
          use RpcElixir.Router, wire_aliases: [{NotARealModule123, RpcElixir.UnixMillis}]
        end
        """)
      end
    end

    test "raises CompileError when a wire_aliases entry maps a module to itself" do
      assert_raise CompileError, ~r/cannot map a module to itself/i, fn ->
        Code.eval_string("""
        defmodule BadAliasRouter2 do
          use RpcElixir.Router, wire_aliases: [{RpcElixir.UnixMillis, RpcElixir.UnixMillis}]
        end
        """)
      end
    end
  end

  describe "wire_aliases resolution" do
    test "maps DateTime.t() to the aliased custom type in the frozen IR" do
      [proc] = RpcElixir.RouterTest.WireAliasRouter.__procedures__()
      created_at = proc.input.fields.created_at

      assert created_at == %{
               kind: "custom",
               module: RpcElixir.UnixMillis,
               inner: %{kind: "primitive", type: "integer"}
             }
    end

    test "without an alias the same DateTime.t() field stays a datetime kind" do
      [proc] = RpcElixir.RouterTest.NoAliasRouter.__procedures__()
      assert proc.input.fields.created_at == %{kind: "datetime"}
    end

    @epoch_millis_custom %{
      kind: "custom",
      module: RpcElixir.UnixMillis,
      inner: %{kind: "primitive", type: "integer"}
    }

    test "alias maps an Ecto :utc_datetime field to the custom kind in the frozen IR" do
      [proc] = RpcElixir.RouterTest.EctoWireAliasRouter.__procedures__()
      assert proc.output.fields.row.fields.created_at == @epoch_millis_custom
    end

    test "without the alias the same Ecto :utc_datetime field stays a datetime kind" do
      [proc] = RpcElixir.RouterTest.EctoNoAliasRouter.__procedures__()
      assert proc.output.fields.row.fields.created_at == %{kind: "datetime"}
    end

    test "alias resolves through list, nullable, and optional wrappers in the frozen IR" do
      [proc] = RpcElixir.RouterTest.WrappedAliasRouter.__procedures__()
      fields = proc.input.fields

      assert fields.many == %{kind: "list", inner: @epoch_millis_custom}
      assert fields.maybe == %{kind: "nullable", inner: @epoch_millis_custom}
      assert fields.lazy == %{kind: "optional", inner: @epoch_millis_custom}
    end

    test "multiple aliases coexist and apply independently in the frozen IR" do
      [proc] = RpcElixir.RouterTest.MultiAliasRouter.__procedures__()
      fields = proc.input.fields

      assert fields.at == @epoch_millis_custom

      assert fields.day == %{
               kind: "custom",
               module: RpcElixir.TypespecFixtures.Sku,
               inner: %{kind: "primitive", type: "string"}
             }
    end
  end
end
