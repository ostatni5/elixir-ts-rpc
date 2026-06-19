defmodule RpcElixir.Types.FromSpecTest.MalformedSpecHandler do
  @moduledoc false
  # Returns a spec AST that is neither `fun(args) :: return` nor a `:when`-bounded
  # variant, so `decompose_spec` reports `{:invalid_spec_shape, _}` instead of raising.
  def weird(input, _ctx), do: {:ok, input}

  def __rpc_specs__ do
    %{{:weird, 2} => quote(do: {:ok, integer()})}
  end
end

defmodule RpcElixir.Types.FromSpecTest do
  use ExUnit.Case, async: true

  alias RpcElixir.Types.FromSpec
  alias RpcElixir.Types.FromSpecTest.MalformedSpecHandler
  alias RpcElixir.Types.RpcConvention
  alias RpcElixir.Types.Walker
  alias RpcElixir.TypespecFixtures.Handlers

  describe "fetch_spec/3" do
    test "resolves local @type aliases in the input arg" do
      assert {:ok, %{args: [input, _ctx], return_ast: return_ast}} =
               FromSpec.fetch_spec(Handlers, :get_user, 2)

      assert input == %{kind: "object", fields: %{id: %{kind: "primitive", type: "integer"}}}
      assert match?({:|, _, _}, return_ast)
    end

    test "leaves the ctx arg as raw AST - it is not part of the wire contract" do
      assert {:ok, %{args: [_input, ctx_ast]}} = FromSpec.fetch_spec(Handlers, :get_user, 2)
      assert match?({:%{}, _, []}, ctx_ast)
    end

    test "accepts a non-wire ctx type (e.g. a struct) without walking it" do
      assert {:ok, %{args: [input, ctx_ast]}} = FromSpec.fetch_spec(Handlers, :with_struct_ctx, 2)
      assert input == %{kind: "object", fields: %{}}
      assert match?({{:., _, [_, :t]}, _, []}, ctx_ast)
    end

    test "resolves a parameterized local @type" do
      assert {:ok, %{args: [input, _ctx]}} = FromSpec.fetch_spec(Handlers, :list_users, 2)
      assert input == %{kind: "object", fields: %{limit: %{kind: "primitive", type: "integer"}}}
    end

    test "resolves a bounded type variable (when var: type)" do
      assert {:ok, %{args: [a, _ctx], return_ast: return_ast}} =
               FromSpec.fetch_spec(Handlers, :echo, 2)

      assert a == %{kind: "primitive", type: "string"}

      {:ok, {output_ast, _error_ast}} = RpcConvention.decompose_return(return_ast)
      assert Walker.walk(output_ast) == %{kind: "primitive", type: "string"}
    end

    test "resolves chained bounded type variables (when a: b, b: integer())" do
      assert {:ok, %{args: [a, _ctx]}} = FromSpec.fetch_spec(Handlers, :chained, 2)
      assert a == %{kind: "primitive", type: "integer"}
    end

    test "returns :no_spec when the function has no @spec" do
      assert {:error, :no_spec} = FromSpec.fetch_spec(Handlers, :no_spec, 2)
    end

    test "returns :no_spec when the function does not exist" do
      assert {:error, :no_spec} = FromSpec.fetch_spec(Handlers, :missing, 2)
    end

    test "returns :module_not_found when the module does not exist" do
      assert {:error, :module_not_found} = FromSpec.fetch_spec(NonExistent.Module, :call, 2)
    end

    test "returns {:invalid_spec_shape, _} (not a raise) for an unexpected spec shape" do
      assert {:error, {:invalid_spec_shape, _ast}} =
               FromSpec.fetch_spec(MalformedSpecHandler, :weird, 2)
    end
  end

  describe "fetch_rpc/2" do
    test "extracts input, output, and error from the RPC convention" do
      assert {:ok, %{input: input, output: output, error: error}} =
               FromSpec.fetch_rpc(Handlers, :get_user)

      assert input == %{kind: "object", fields: %{id: %{kind: "primitive", type: "integer"}}}

      assert output == %{
               kind: "object",
               fields: %{
                 id: %{kind: "primitive", type: "integer"},
                 name: %{kind: "primitive", type: "string"}
               }
             }

      assert error == %{kind: "enum", values: ["not_found"]}
    end

    test "error is nil when the spec has no {:error, _} variant" do
      assert {:ok, %{error: nil, output: output}} = FromSpec.fetch_rpc(Handlers, :list_users)
      assert match?(%{kind: "list"}, output)
    end

    test "tolerates a non-wire ctx type (e.g. a struct) - ctx is not part of the contract" do
      assert {:ok, %{input: input, output: output, error: nil}} =
               FromSpec.fetch_rpc(Handlers, :with_struct_ctx)

      assert input == %{kind: "object", fields: %{}}
      assert output == %{kind: "object", fields: %{}}
    end

    test "returns :no_spec when the function has no @spec" do
      assert {:error, :no_spec} = FromSpec.fetch_rpc(Handlers, :no_spec)
    end

    test "returns {:error, {:invalid_return, _}} for a non-RPC return type" do
      assert {:error, {:invalid_return, _}} = FromSpec.fetch_rpc(Handlers, :status)
    end

    test "threads {:invalid_spec_shape, _} through instead of raising" do
      assert {:error, {:invalid_spec_shape, _ast}} =
               FromSpec.fetch_rpc(MalformedSpecHandler, :weird)
    end
  end
end
