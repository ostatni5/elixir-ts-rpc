defmodule RpcElixir.HandlerTest do
  use ExUnit.Case, async: true

  alias RpcElixir.Types.FromSpec

  defmodule InModuleHandler do
    use RpcElixir.Handler

    @type user :: %{id: String.t(), email: String.t()}
    @type page(t) :: %{items: [t], next: String.t() | nil}
    @typep counter :: integer()
    @opaque token :: String.t()

    @spec _bump(counter()) :: counter()
    defp _bump(c), do: c + 1

    @spec list(input :: %{}, ctx :: %{}) :: {:ok, %{users: [user()]}} | {:error, :forbidden}
    def list(_input, _ctx), do: {:ok, %{users: []}}

    @spec get(input :: %{id: String.t()}, ctx :: %{}) :: {:ok, user()} | {:error, :not_found}
    def get(%{id: _id}, _ctx), do: {:error, :not_found}

    @spec echo(a, %{}) :: {:ok, a} when a: String.t()
    def echo(a, _ctx), do: {:ok, a}

    @spec page_users(input :: %{}, ctx :: %{}) :: {:ok, page(user())}
    def page_users(_input, _ctx), do: {:ok, %{items: [], next: nil}}

    # Private function with @spec — should NOT appear in __rpc_specs__/0.
    @spec _helper(integer()) :: integer()
    defp _helper(x), do: _bump(x)

    # Public arity-1 — allowed (future no-ctx handler shape).
    @spec arity_one(input :: %{}) :: {:ok, %{}}
    def arity_one(_input), do: {:ok, %{}}

    # Compile-only reference so the helper isn't flagged "unused".
    def _use_helper, do: _helper(0)
  end

  defmodule NoSpecHandler do
    use RpcElixir.Handler

    def hello(_), do: :ok
  end

  describe "__rpc_specs__/0 capture and filtering" do
    test "exposes captured specs keyed by {fun, arity}" do
      specs = InModuleHandler.__rpc_specs__()
      assert Map.has_key?(specs, {:list, 2})
      assert Map.has_key?(specs, {:get, 2})
      assert Map.has_key?(specs, {:echo, 2})
      assert Map.has_key?(specs, {:arity_one, 1})
    end

    test "drops specs on private defs and on functions outside arity 1/2" do
      specs = InModuleHandler.__rpc_specs__()
      refute Map.has_key?(specs, {:_helper, 1}), "private @spec should be filtered out"
    end

    test "captured spec AST has named-arg labels stripped" do
      %{{:get, 2} => ast} = InModuleHandler.__rpc_specs__()
      {:"::", _, [{:get, _, args}, _return]} = ast
      # Arg should be the bare map type, not `input :: %{...}`
      Enum.each(args, fn arg ->
        refute match?({:"::", _, [{name, _, ctx}, _]} when is_atom(name) and is_atom(ctx), arg),
               "named-arg wrapper should be stripped, got: #{Macro.to_string(arg)}"
      end)
    end

    test "empty spec map for handler with no @spec entries" do
      assert NoSpecHandler.__rpc_specs__() == %{}
    end
  end

  describe "FromSpec integration via in-module accessor" do
    test "resolves a simple spec" do
      assert {:ok, %{input: input, output: output, error: error}} =
               FromSpec.fetch_rpc(InModuleHandler, :list)

      assert input == %{kind: "object", fields: %{}}
      assert match?(%{kind: "object", fields: %{users: %{kind: "list", inner: _}}}, output)
      assert error == %{kind: "enum", values: ["forbidden"]}
    end

    test "resolves a local @type" do
      assert {:ok, %{output: output}} = FromSpec.fetch_rpc(InModuleHandler, :get)

      assert output == %{
               kind: "object",
               fields: %{
                 id: %{kind: "primitive", type: "string"},
                 email: %{kind: "primitive", type: "string"}
               }
             }
    end

    test "resolves a `when`-bounded spec variable" do
      assert {:ok, %{input: input, output: output}} =
               FromSpec.fetch_rpc(InModuleHandler, :echo)

      assert input == %{kind: "primitive", type: "string"}
      assert output == %{kind: "primitive", type: "string"}
    end

    test "resolves a parameterized @type" do
      assert {:ok, %{output: output}} =
               FromSpec.fetch_rpc(InModuleHandler, :page_users)

      assert match?(%{kind: "object", fields: %{items: %{kind: "list", inner: _}}}, output)
    end

    test "no_spec when handler has no @spec for that function" do
      assert {:error, :no_spec} = FromSpec.fetch_rpc(NoSpecHandler, :hello)
    end
  end

  describe "BEAM fallback (handler without `use RpcElixir.Handler`)" do
    test "FromSpec still resolves via Code.Typespec.fetch_specs for legacy handlers" do
      # `RpcElixir.TypespecFixtures.Handlers` is a support-file module that does
      # NOT use RpcElixir.Handler. The full surface is exercised by
      # `from_spec_test.exs`; this assertion just locks in the fact that the
      # in-module accessor is genuinely absent and the BEAM path still works.
      refute function_exported?(RpcElixir.TypespecFixtures.Handlers, :__rpc_specs__, 0)

      assert {:ok, _} = FromSpec.fetch_rpc(RpcElixir.TypespecFixtures.Handlers, :get_user)
    end
  end

  describe "__rpc_types__/0" do
    test "captures zero-arity, parameterized, typep, and opaque types" do
      types = InModuleHandler.__rpc_types__()

      assert Map.has_key?(types, {:user, 0})
      {[], _user_body} = Map.fetch!(types, {:user, 0})

      assert Map.has_key?(types, {:page, 1})
      {[var], _page_body} = Map.fetch!(types, {:page, 1})
      assert var == :t

      assert Map.has_key?(types, {:counter, 0})
      assert Map.has_key?(types, {:token, 0})
    end
  end
end
