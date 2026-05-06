defmodule RpcElixir.WalkerTest do
  @moduledoc """
  Unit tests for the typespec AST walker (`Types.Walker`).
  Production callers use `RpcElixir.Types.FromSpec` instead. These tests
  exercise the walker in isolation against quoted AST.
  """

  use ExUnit.Case, async: true

  alias RpcElixir.Types.RpcConvention
  alias RpcElixir.Types.Walker
  alias RpcElixir.TypespecFixtures.Money
  alias RpcElixir.TypespecFixtures.Product

  @product Product
  @schema RpcElixir.TypespecFixtures.FakeSchema
  @rejected_schema RpcElixir.TypespecFixtures.RejectedMapSchema

  # Cycle and diamond fixtures must be compiled to real .beam files so
  # Code.Typespec.fetch_types/1 can read their debug info. Modules defined in
  # .exs files are interpreted in-memory and lack an on-disk beam, so we
  # compile them via elixirc once per test suite run.
  @cycle_diamond_source """
  defmodule RpcElixir.WalkerTest.Fixtures.CycleA do
    defstruct b: nil
    @type t :: %__MODULE__{b: RpcElixir.WalkerTest.Fixtures.CycleB.t()}
  end

  defmodule RpcElixir.WalkerTest.Fixtures.CycleB do
    defstruct a: nil
    @type t :: %__MODULE__{a: RpcElixir.WalkerTest.Fixtures.CycleA.t()}
  end

  defmodule RpcElixir.WalkerTest.Fixtures.DiamondLeaf do
    defstruct value: ""
    @type t :: %__MODULE__{value: String.t()}
  end

  defmodule RpcElixir.WalkerTest.Fixtures.DiamondLeft do
    defstruct leaf: nil
    @type t :: %__MODULE__{leaf: RpcElixir.WalkerTest.Fixtures.DiamondLeaf.t()}
  end

  defmodule RpcElixir.WalkerTest.Fixtures.DiamondRight do
    defstruct leaf: nil
    @type t :: %__MODULE__{leaf: RpcElixir.WalkerTest.Fixtures.DiamondLeaf.t()}
  end

  defmodule RpcElixir.WalkerTest.Fixtures.DiamondRoot do
    defstruct left: nil, right: nil

    @type t :: %__MODULE__{
            left: RpcElixir.WalkerTest.Fixtures.DiamondLeft.t(),
            right: RpcElixir.WalkerTest.Fixtures.DiamondRight.t()
          }
  end

  defmodule RpcElixir.WalkerTest.Fixtures.NonStructCycleA do
    @type t :: RpcElixir.WalkerTest.Fixtures.NonStructCycleB.t()
  end

  defmodule RpcElixir.WalkerTest.Fixtures.NonStructCycleB do
    @type t :: RpcElixir.WalkerTest.Fixtures.NonStructCycleA.t()
  end
  """

  setup_all do
    tmp = System.tmp_dir!()
    src = Path.join(tmp, "walker_cycle_fixtures.ex")
    File.write!(src, @cycle_diamond_source)
    {_out, 0} = System.cmd("elixirc", ["-o", tmp, src], stderr_to_stdout: true)
    :code.add_path(String.to_charlist(tmp))
    Code.ensure_compiled(RpcElixir.WalkerTest.Fixtures.CycleA)
    Code.ensure_compiled(RpcElixir.WalkerTest.Fixtures.CycleB)
    Code.ensure_compiled(RpcElixir.WalkerTest.Fixtures.DiamondRoot)
    Code.ensure_compiled(RpcElixir.WalkerTest.Fixtures.NonStructCycleA)
    Code.ensure_compiled(RpcElixir.WalkerTest.Fixtures.NonStructCycleB)
    :ok
  end

  describe "primitives" do
    test "primitive type ASTs map to their expected kinds" do
      for {ast, expected} <- [
            {quote(do: String.t()), %{kind: "primitive", type: "string"}},
            {quote(do: binary()), %{kind: "primitive", type: "string"}},
            {quote(do: integer()), %{kind: "primitive", type: "integer"}},
            {quote(do: non_neg_integer()), %{kind: "primitive", type: "integer"}},
            {quote(do: pos_integer()), %{kind: "primitive", type: "integer"}},
            {quote(do: float()), %{kind: "primitive", type: "float"}},
            {quote(do: boolean()), %{kind: "primitive", type: "boolean"}},
            {quote(do: number()), %{kind: "primitive", type: "float"}}
          ] do
        assert Walker.walk(ast) == expected
      end
    end
  end

  describe "nullable" do
    test "T | nil" do
      assert Walker.walk(quote do: String.t() | nil) ==
               %{kind: "nullable", inner: %{kind: "primitive", type: "string"}}
    end

    test "nil | T" do
      assert Walker.walk(quote do: nil | integer()) ==
               %{kind: "nullable", inner: %{kind: "primitive", type: "integer"}}
    end
  end

  describe "lists" do
    test "[T]" do
      assert Walker.walk(quote do: [String.t()]) ==
               %{kind: "list", inner: %{kind: "primitive", type: "string"}}
    end

    test "list(T)" do
      assert Walker.walk(quote do: list(integer())) ==
               %{kind: "list", inner: %{kind: "primitive", type: "integer"}}
    end
  end

  describe "maps" do
    test "required fields" do
      assert Walker.walk(quote do: %{id: String.t(), count: integer()}) == %{
               kind: "object",
               fields: %{
                 id: %{kind: "primitive", type: "string"},
                 count: %{kind: "primitive", type: "integer"}
               }
             }
    end

    test "optional(:key) => T" do
      assert Walker.walk(quote do: %{optional(:name) => String.t()}) == %{
               kind: "object",
               fields: %{
                 name: %{kind: "optional", inner: %{kind: "primitive", type: "string"}}
               }
             }
    end

    test "required(:key) => T" do
      assert Walker.walk(quote do: %{required(:id) => String.t()}) == %{
               kind: "object",
               fields: %{id: %{kind: "primitive", type: "string"}}
             }
    end

    test "mixed required and optional fields" do
      result =
        Walker.walk(quote do: %{required(:id) => String.t(), optional(:name) => String.t()})

      assert result.fields.id == %{kind: "primitive", type: "string"}

      assert result.fields.name == %{
               kind: "optional",
               inner: %{kind: "primitive", type: "string"}
             }
    end

    test "nested map" do
      assert Walker.walk(quote do: %{profile: %{bio: String.t() | nil}}) == %{
               kind: "object",
               fields: %{
                 profile: %{
                   kind: "object",
                   fields: %{
                     bio: %{kind: "nullable", inner: %{kind: "primitive", type: "string"}}
                   }
                 }
               }
             }
    end
  end

  describe "enums (atom literals)" do
    test "single atom literal" do
      assert Walker.walk(quote do: :draft) == %{kind: "enum", values: ["draft"]}
    end

    test "atom union" do
      result = Walker.walk(quote do: :draft | :published | :archived)
      assert result.kind == "enum"
      assert Enum.sort(result.values) == ["archived", "draft", "published"]
    end
  end

  describe "RpcConvention.decompose_return/1" do
    test "{:ok, T} | {:error, E}" do
      ast = quote do: {:ok, String.t()} | {:error, :not_found}
      {:ok, {output, error}} = RpcConvention.decompose_return(ast)
      assert output == quote(do: String.t())
      assert error == :not_found
    end

    test "only {:ok, T}" do
      ast = quote do: {:ok, integer()}
      {:ok, {output, error}} = RpcConvention.decompose_return(ast)
      assert output == quote(do: integer())
      assert error == nil
    end

    test "error variant as atom union" do
      ast = quote do: {:ok, integer()} | {:error, :not_found | :invalid}
      {:ok, {_output, error}} = RpcConvention.decompose_return(ast)
      parsed = Walker.walk(error)
      assert parsed.kind == "enum"
      assert Enum.sort(parsed.values) == ["invalid", "not_found"]
    end

    test "no {:ok, _} variant returns :no_ok_variant error" do
      ast = quote do: {:error, :not_found}
      assert RpcConvention.decompose_return(ast) == {:error, :no_ok_variant}
    end
  end

  describe "Mod.t() forms" do
    test "stdlib/external Mod.t() forms map to their expected kinds" do
      for {ast, expected} <- [
            {quote(do: DateTime.t()), %{kind: "datetime"}},
            {quote(do: Date.t()), %{kind: "date"}},
            {quote(do: NaiveDateTime.t()), %{kind: "naive_datetime"}},
            {quote(do: Time.t()), %{kind: "time"}},
            {quote(do: Decimal.t()), %{kind: "decimal"}}
          ] do
        assert Walker.walk(ast) == expected
      end
    end

    test "Mod.t() resolves struct via @type t :: %__MODULE__{...}" do
      # credo:disable-for-next-line Credo.Check.Design.AliasUsage
      assert Walker.walk(quote(do: RpcElixir.TypespecFixtures.Product.t())) == %{
               kind: "object",
               struct: Product,
               fields: %{
                 id: %{kind: "primitive", type: "integer"},
                 name: %{kind: "primitive", type: "string"}
               }
             }
    end

    test "Mod.t() resolves when @type t aliases a primitive" do
      # credo:disable-for-next-line Credo.Check.Design.AliasUsage
      assert Walker.walk(quote(do: RpcElixir.TypespecFixtures.StringAlias.t())) == %{
               kind: "primitive",
               type: "string"
             }
    end

    test "expanded-atom Mod.t() (as produced by alias expansion in handler.ex)" do
      ast = {{:., [], [@product, :t]}, [], []}
      assert Walker.walk(ast).struct == @product
    end

    test "Mod.t() for module without struct or @type t raises" do
      assert_raise ArgumentError, ~r/cannot resolve.*\.t\(\)/, fn ->
        # credo:disable-for-next-line Credo.Check.Design.AliasUsage
        Walker.walk(quote(do: RpcElixir.TypespecFixtures.Empty.t()))
      end
    end
  end

  describe "CustomType behaviour" do
    test "Mod.t() for a module implementing CustomType resolves to custom kind" do
      # credo:disable-for-next-line Credo.Check.Design.AliasUsage
      assert Walker.walk(quote(do: RpcElixir.TypespecFixtures.Money.t())) == %{
               kind: "custom",
               module: Money,
               inner: %{kind: "primitive", type: "string"}
             }
    end
  end

  describe "errors on unsupported forms" do
    test "unsupported ASTs raise ArgumentError with actionable messages" do
      for {ast, pattern} <- [
            {quote(do: any()), ~r/any\(\) is not allowed/},
            {quote(do: term()), ~r/term\(\) is not allowed/},
            {quote(do: map()), ~r/map\(\) is not allowed/},
            {quote(do: atom()), ~r/unsupported typespec/},
            {quote(do: String.t() | integer()), ~r/unsupported union/}
          ] do
        assert_raise ArgumentError, pattern, fn -> Walker.walk(ast) end
      end
    end
  end

  describe "unknown local types" do
    test "unknown local type raises with helpful message" do
      assert_raise ArgumentError, ~r/local @type not found/, fn ->
        Walker.walk(quote(do: unknown_type(String.t())))
      end
    end
  end

  describe "empty collection edges" do
    test "empty map %{} resolves to object with no fields" do
      assert Walker.walk(quote do: %{}) == %{kind: "object", fields: %{}}
    end

    test "empty list [] raises" do
      assert_raise ArgumentError, fn ->
        Walker.walk(quote do: [])
      end
    end
  end

  describe "self-referential @type" do
    test "Tree.t() resolves to a self-referential struct IR (children field references Tree by name)" do
      # credo:disable-for-next-line Credo.Check.Design.AliasUsage
      result = Walker.walk(quote do: RpcElixir.TypespecFixtures.Tree.t())
      assert result.kind == "object"
      assert result.struct == RpcElixir.TypespecFixtures.Tree
      assert result.fields.value == %{kind: "primitive", type: "integer"}
      children_ir = result.fields.children
      assert children_ir.kind == "list"
      # The list's inner type is a truncated self-reference, not a fully inlined copy.
      assert children_ir.inner == %{
               kind: "object",
               struct: RpcElixir.TypespecFixtures.Tree,
               fields: %{}
             }
    end
  end

  describe "mutually-recursive types" do
    test "struct A.t() <-> struct B.t() resolves. The back-reference is a truncated struct ref" do
      # credo:disable-for-next-line Credo.Check.Design.AliasUsage
      result = Walker.walk(quote do: RpcElixir.WalkerTest.Fixtures.CycleA.t())
      assert result.kind == "object"
      assert result.struct == RpcElixir.WalkerTest.Fixtures.CycleA
      b_ref = result.fields.b
      assert b_ref.kind == "object"
      assert b_ref.struct == RpcElixir.WalkerTest.Fixtures.CycleB
      # B's `a` field is the truncated back-reference to A (empty fields, not re-walked).
      assert b_ref.fields.a == %{
               kind: "object",
               struct: RpcElixir.WalkerTest.Fixtures.CycleA,
               fields: %{}
             }
    end

    test "non-struct mutual recursion raises a helpful error" do
      assert_raise ArgumentError, ~r/recursive type detected/, fn ->
        Walker.walk(quote do: RpcElixir.WalkerTest.Fixtures.NonStructCycleA.t())
      end
    end

    test "non-cyclic diamond (A->B,C->D) resolves without raising" do
      result = Walker.walk(quote do: RpcElixir.WalkerTest.Fixtures.DiamondRoot.t())
      assert result.kind == "object"
      assert result.struct == RpcElixir.WalkerTest.Fixtures.DiamondRoot
      assert Map.has_key?(result.fields, :left)
      assert Map.has_key?(result.fields, :right)
      assert result.fields.left.kind == "object"
      assert result.fields.right.kind == "object"
      assert result.fields.left.fields.leaf.kind == "object"
      assert result.fields.right.fields.leaf.kind == "object"
    end
  end

  describe "inline struct literal in @spec" do
    test "%Mod{field: T, ...} resolves to object with :struct marker" do
      assert Walker.walk(quote do: %unquote(@product){id: integer(), name: String.t()}) == %{
               kind: "object",
               struct: @product,
               fields: %{
                 id: %{kind: "primitive", type: "integer"},
                 name: %{kind: "primitive", type: "string"}
               }
             }
    end

    test "bare %Mod{} (no field types) falls back to Mod.t() resolution" do
      assert Walker.walk(quote do: %unquote(@product){}) == %{
               kind: "object",
               struct: @product,
               fields: %{
                 id: %{kind: "primitive", type: "integer"},
                 name: %{kind: "primitive", type: "string"}
               }
             }
    end
  end

  describe "Ecto schema field type mapping" do
    test "all Ecto field types map to the documented internal kinds" do
      result = Walker.walk(quote(do: unquote(@schema).t()))

      assert result.kind == "object"
      assert result.struct == @schema

      assert result.fields == %{
               id: %{kind: "primitive", type: "integer"},
               name: %{kind: "primitive", type: "string"},
               score: %{kind: "primitive", type: "integer"},
               weight: %{kind: "primitive", type: "float"},
               active: %{kind: "primitive", type: "boolean"},
               birthday: %{kind: "date"},
               created_at_usec: %{kind: "datetime"},
               created_at: %{kind: "datetime"},
               updated_local: %{kind: "naive_datetime"},
               updated_local_usec: %{kind: "naive_datetime"},
               start_time: %{kind: "time"},
               balance: %{kind: "decimal"},
               uuid: %{kind: "primitive", type: "string"},
               tags: %{kind: "list", inner: %{kind: "primitive", type: "string"}}
             }
    end

    test ":map field type is rejected with actionable error" do
      assert_raise ArgumentError, ~r/Ecto field type :map is not allowed/, fn ->
        Walker.walk(quote(do: unquote(@rejected_schema).t()))
      end
    end
  end
end
