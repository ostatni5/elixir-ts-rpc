defmodule RpcElixir.TypesTestFixtures.ThrowingBrand do
  @moduledoc false
  @behaviour RpcElixir.CustomType
  @type t :: integer()
  @impl true
  def wire_spec, do: %{kind: "primitive", type: "string"}
  @impl true
  def serialize(_v), do: throw(:boom)
end

defmodule RpcElixir.TypesTestFixtures.ExitingBrand do
  @moduledoc false
  @behaviour RpcElixir.CustomType
  @type t :: integer()
  @impl true
  def wire_spec, do: %{kind: "primitive", type: "string"}
  @impl true
  def serialize(_v), do: exit(:boom)
end

defmodule RpcElixir.TypesTestFixtures.PermissiveBrand do
  @moduledoc false
  @behaviour RpcElixir.CustomType
  @type t :: integer()
  @impl true
  def wire_spec, do: %{kind: "primitive", type: "string"}
  # Deliberately accepts anything — the danger the input path must guard against.
  @impl true
  def serialize(v), do: inspect(v)
end

defmodule RpcElixir.TypesTest do
  use ExUnit.Case, async: true

  alias RpcElixir.Types

  describe "resolve/1 inline shorthand" do
    for {atom, type} <- [string: "string", integer: "integer", float: "float", boolean: "boolean"] do
      test "primitive :#{atom}" do
        assert Types.resolve(unquote(atom)) == %{kind: "primitive", type: unquote(type)}
      end
    end

    for {tag, inner_atom, inner_type, expected_kind} <- [
          {:optional, :string, "string", "optional"},
          {:nullable, :integer, "integer", "nullable"},
          {:list, :string, "string", "list"},
          {:stream, :integer, "integer", "list"}
        ] do
      test "{#{inspect(tag)}, t} resolves to kind=#{expected_kind}" do
        assert Types.resolve({unquote(tag), unquote(inner_atom)}) == %{
                 kind: unquote(expected_kind),
                 inner: %{kind: "primitive", type: unquote(inner_type)}
               }
      end
    end

    test "plain map → object" do
      assert Types.resolve(%{id: :integer, name: :string}) == %{
               kind: "object",
               fields: %{
                 id: %{kind: "primitive", type: "integer"},
                 name: %{kind: "primitive", type: "string"}
               }
             }
    end

    test "already-resolved %{kind: ...} passes through unchanged" do
      already = %{kind: "primitive", type: "string"}
      assert Types.resolve(already) == already
    end
  end

  describe "resolve/1 catch-all" do
    test "unsupported atom raises ArgumentError with hint" do
      assert_raise ArgumentError, ~r/unsupported inline spec/, fn ->
        Types.resolve(:atom)
      end
    end

    test "struct value raises ArgumentError" do
      assert_raise ArgumentError, ~r/unsupported inline spec/, fn ->
        Types.resolve(%Date{year: 2025, month: 1, day: 1})
      end
    end
  end

  describe "validate/2 happy paths" do
    test "string primitive" do
      assert {:ok, "hello"} = Types.validate(:string, "hello")
    end

    test "integer primitive" do
      assert {:ok, 42} = Types.validate(:integer, 42)
    end

    test "boolean primitive" do
      assert {:ok, true} = Types.validate(:boolean, true)
    end

    test "nullable accepts nil" do
      assert {:ok, nil} = Types.validate({:nullable, :string}, nil)
    end

    test "nullable accepts value of inner type" do
      assert {:ok, "hi"} = Types.validate({:nullable, :string}, "hi")
    end

    test "optional field can be absent from object" do
      assert {:ok, %{}} = Types.validate(%{name: {:optional, :string}}, %{})
    end

    test "optional field accepted when present" do
      assert {:ok, %{name: "bob"}} = Types.validate(%{name: {:optional, :string}}, %{name: "bob"})
    end

    test "list of strings" do
      assert {:ok, ["a", "b"]} = Types.validate({:list, :string}, ["a", "b"])
    end

    test "object with string keys coerced to atoms" do
      assert {:ok, %{id: "abc"}} = Types.validate(%{id: :string}, %{"id" => "abc"})
    end
  end

  describe "validate/2 failure cases" do
    test "missing required field" do
      assert {:error, %{"email" => ["missing required field"]}} =
               Types.validate(%{id: :string, email: :string}, %{id: "x"})
    end

    test "wrong primitive type" do
      assert {:error, %{"_" => [msg]}} = Types.validate(:integer, "not an int")
      assert msg =~ "expected"
    end

    test "list with wrong element type" do
      assert {:error, %{"1" => %{"_" => [msg]}}} =
               Types.validate({:list, :integer}, [1, "two", 3])

      assert msg =~ "expected"
    end

    test "object with wrong field type" do
      assert {:error, %{"count" => %{"_" => [msg]}}} =
               Types.validate(%{count: :integer}, %{count: "five"})

      assert msg =~ "expected"
    end

    test "nested field errors" do
      assert {:error, %{"profile" => %{"bio" => ["missing required field"]}}} =
               Types.validate(%{profile: %{bio: :string}}, %{profile: %{}})
    end

    test "unexpected fields are rejected" do
      assert {:error, %{"extra" => ["unexpected field"]}} =
               Types.validate(%{id: :string}, %{id: "x", extra: "nope"})
    end

    test "unexpected field errors merge with missing field errors" do
      assert {:error, errors} =
               Types.validate(%{id: :string, email: :string}, %{id: "x", typo: "nope"})

      assert errors["typo"] == ["unexpected field"]
      assert errors["email"] == ["missing required field"]
    end

    test "enum value whose atom was never materialized returns an error, never raises" do
      never_seen = "rpc_enum_never_materialized_#{System.unique_integer([:positive])}"
      spec = %{kind: "enum", values: [never_seen]}

      assert {:error, %{"_" => [msg]}} = Types.validate(spec, never_seen)
      assert msg =~ "expected one of"
    end
  end

  describe "CustomType behaviour" do
    alias RpcElixir.TypespecFixtures.Money

    @money_spec %{kind: "custom", module: Money, inner: %{kind: "primitive", type: "string"}}

    test "serialize/2 calls module.serialize and passes result through inner spec" do
      assert Types.serialize(@money_spec, %Money{amount: 100, currency: "USD"}) == "100 USD"
    end

    test "serialize/2 works nested in an object" do
      spec = %{price: @money_spec}

      assert Types.serialize(spec, %{price: %Money{amount: 50, currency: "EUR"}}) == %{
               price: "50 EUR"
             }
    end

    test "validate/2 accepts a wire-shaped value (input path)" do
      assert {:ok, "100 USD"} = Types.validate(@money_spec, "100 USD")
    end

    test "validate/2 accepts a source value (output path), deferring to serialize" do
      money = %Money{amount: 100, currency: "USD"}
      assert {:ok, ^money} = Types.validate(@money_spec, money)
    end

    test "serialize/2 emits a string wire value for a branded custom (Int64String)" do
      alias RpcElixir.TypespecFixtures.Int64

      spec = %{kind: "custom", module: Int64, inner: %{kind: "primitive", type: "string"}}

      result = Types.serialize(spec, 9_007_199_254_740_993)

      assert result == "9007199254740993"
      assert is_binary(result), "the Int64String brand promises a string, never a JS number"
    end

    test "validate/2 then serialize/2 round-trips a branded custom source value (output path)" do
      alias RpcElixir.TypespecFixtures.Int64

      spec = %{kind: "custom", module: Int64, inner: %{kind: "primitive", type: "string"}}

      assert {:ok, 9_007_199_254_740_993} = Types.validate(spec, 9_007_199_254_740_993)
      assert Types.serialize(spec, 9_007_199_254_740_993) == "9007199254740993"
    end
  end

  describe "validate/2 temporal input parsing" do
    test "date: valid ISO string parses to a Date struct" do
      assert {:ok, ~D[2024-01-15]} = Types.validate(%{kind: "date"}, "2024-01-15")
    end

    test "date: malformed string is rejected" do
      assert {:error, %{"_" => [msg]}} = Types.validate(%{kind: "date"}, "totally-not-a-date")
      assert msg =~ "ISO 8601 date"
    end

    test "date: already a Date struct passes through (idempotent fast-path)" do
      assert {:ok, ~D[2024-01-15]} = Types.validate(%{kind: "date"}, ~D[2024-01-15])
    end

    test "naive_datetime: valid ISO string parses to a NaiveDateTime struct" do
      assert {:ok, ~N[2024-01-15 10:30:00]} =
               Types.validate(%{kind: "naive_datetime"}, "2024-01-15T10:30:00")
    end

    test "naive_datetime: malformed string is rejected" do
      assert {:error, %{"_" => [_]}} = Types.validate(%{kind: "naive_datetime"}, "nope")
    end

    test "naive_datetime: already a struct passes through" do
      assert {:ok, ~N[2024-01-15 10:30:00]} =
               Types.validate(%{kind: "naive_datetime"}, ~N[2024-01-15 10:30:00])
    end

    test "time: valid ISO string parses to a Time struct" do
      assert {:ok, ~T[10:30:00]} = Types.validate(%{kind: "time"}, "10:30:00")
    end

    test "time: malformed string is rejected" do
      assert {:error, %{"_" => [_]}} = Types.validate(%{kind: "time"}, "25:99:99")
    end

    test "time: already a struct passes through" do
      assert {:ok, ~T[10:30:00]} = Types.validate(%{kind: "time"}, ~T[10:30:00])
    end

    test "datetime: already a DateTime struct passes through" do
      dt = ~U[2024-01-15 10:30:00Z]
      assert {:ok, ^dt} = Types.validate(%{kind: "datetime"}, dt)
    end

    test "malformed temporal input is rejected at object boundary with field key present" do
      assert {:error, errors} =
               Types.validate(%{born_after: %{kind: "date"}}, %{born_after: "junk"})

      assert Map.has_key?(errors, "born_after")
    end
  end

  describe "validate/2 decimal input parsing" do
    test "valid decimal string parses to a Decimal struct" do
      assert {:ok, decimal} = Types.validate(%{kind: "decimal"}, "12.34")
      assert Decimal.equal?(decimal, Decimal.new("12.34"))
    end

    test "malformed decimal string is rejected (no raise on untrusted input)" do
      assert {:error, %{"_" => [msg]}} = Types.validate(%{kind: "decimal"}, "not-a-number")
      assert msg =~ "decimal"
    end

    test "partial parse (trailing garbage) is rejected" do
      assert {:error, %{"_" => [_]}} = Types.validate(%{kind: "decimal"}, "12.34xyz")
    end

    test "already a Decimal struct passes through (fast-path)" do
      d = Decimal.new("99.9")
      assert {:ok, ^d} = Types.validate(%{kind: "decimal"}, d)
    end
  end

  describe "CustomType: malformed input rejection" do
    alias RpcElixir.TypespecFixtures.{Int64, Money}

    test "value matching neither wire nor source type is rejected for module custom type" do
      spec = %{kind: "custom", module: Int64, inner: %{kind: "primitive", type: "string"}}
      assert {:error, %{"_" => [msg]}} = Types.validate(spec, %{garbage: true})
      assert msg =~ "wire spec nor source type"
    end

    test "valid wire value (string) is still accepted on input path" do
      spec = %{kind: "custom", module: Int64, inner: %{kind: "primitive", type: "string"}}
      assert {:ok, _} = Types.validate(spec, "9007199254740993")
    end

    test "source value (integer) still passes on output path" do
      spec = %{kind: "custom", module: Int64, inner: %{kind: "primitive", type: "string"}}
      assert {:ok, 9_007_199_254_740_993} = Types.validate(spec, 9_007_199_254_740_993)
    end

    test "struct source value passes but wrong struct is rejected" do
      spec = %{kind: "custom", module: Money, inner: %{kind: "primitive", type: "string"}}
      assert {:ok, _} = Types.validate(spec, %Money{amount: 10, currency: "USD"})
      assert {:error, %{"_" => [_]}} = Types.validate(spec, %{amount: 10, currency: "USD"})
    end
  end

  describe "CustomType: serialize/1 that throws or exits on the input path" do
    alias RpcElixir.TypesTestFixtures.{ExitingBrand, ThrowingBrand}

    test "a throwing serialize/1 becomes a leaf error, not a crash" do
      spec = %{kind: "custom", module: ThrowingBrand, inner: %{kind: "primitive", type: "string"}}
      assert {:error, %{"_" => [msg]}} = Types.validate(spec, 123)
      assert msg =~ "wire spec nor source type"
      assert msg =~ "throw"
    end

    test "an exiting serialize/1 becomes a leaf error, not a crash" do
      spec = %{kind: "custom", module: ExitingBrand, inner: %{kind: "primitive", type: "string"}}
      assert {:error, %{"_" => [msg]}} = Types.validate(spec, 123)
      assert msg =~ "wire spec nor source type"
      assert msg =~ "exit"
    end
  end

  describe "CustomType: permissive serialize/1 cannot bypass input validation" do
    alias RpcElixir.TypespecFixtures.DeserializingId
    alias RpcElixir.TypesTestFixtures.PermissiveBrand

    @permissive_spec %{
      kind: "custom",
      module: PermissiveBrand,
      inner: %{kind: "primitive", type: "string"}
    }

    test "(a) malformed map input is rejected even though serialize/1 accepts it" do
      assert {:error, %{"_" => [msg]}} = Types.validate(@permissive_spec, %{evil: true})
      assert msg =~ "wire spec nor source type"
    end

    test "(a) malformed list input is rejected even though serialize/1 accepts it" do
      assert {:error, %{"_" => [_]}} = Types.validate(@permissive_spec, [1, 2, 3])
    end

    test "(b) a valid wire value still deserializes via deserialize/1" do
      spec = %{
        kind: "custom",
        module: DeserializingId,
        inner: %{kind: "primitive", type: "string"}
      }

      assert {:ok, 42} = Types.validate(spec, "42")
    end

    test "(c) a genuine in-process domain scalar is still accepted" do
      assert {:ok, 9_007_199_254_740_993} =
               Types.validate(@permissive_spec, 9_007_199_254_740_993)
    end
  end

  describe "CustomType deserialize callback (input dual of serialize)" do
    alias RpcElixir.TypespecFixtures.{DeserializingId, Money}

    test "validate maps a wire value to the domain value via deserialize/1" do
      spec = %{
        kind: "custom",
        module: DeserializingId,
        inner: %{kind: "primitive", type: "string"}
      }

      assert {:ok, 42} = Types.validate(spec, "42")
    end

    test "validate rejects when deserialize/1 returns {:error, _}" do
      spec = %{
        kind: "custom",
        module: DeserializingId,
        inner: %{kind: "primitive", type: "string"}
      }

      assert {:error, %{"_" => [_]}} = Types.validate(spec, "not-an-int")
    end

    test "without a deserialize/1 callback the wire-validated value is returned (backward compat)" do
      spec = %{kind: "custom", module: Money, inner: %{kind: "primitive", type: "string"}}
      assert {:ok, "100 USD"} = Types.validate(spec, "100 USD")
    end
  end

  describe "optional + nullable composition" do
    @spec_optional_nullable %{name: {:optional, {:nullable, :string}}}

    test "validates a nil value for the field" do
      assert {:ok, %{name: nil}} = Types.validate(@spec_optional_nullable, %{name: nil})
    end

    test "validates an absent field" do
      assert {:ok, result} = Types.validate(@spec_optional_nullable, %{})
      refute Map.has_key?(result, :name)
    end

    test "serialize/2 omits an absent optional field rather than emitting nil" do
      result = Types.serialize(@spec_optional_nullable, %{})
      refute Map.has_key?(result, :name)
    end
  end
end
