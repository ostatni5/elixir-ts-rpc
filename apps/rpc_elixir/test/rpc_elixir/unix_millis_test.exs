defmodule RpcElixir.UnixMillisTest do
  use ExUnit.Case, async: true

  alias RpcElixir.Types
  alias RpcElixir.UnixMillis

  @spec_ %{kind: "custom", module: UnixMillis, inner: %{kind: "primitive", type: "integer"}}

  describe "round-trip through Types" do
    test "serialize turns a DateTime into epoch milliseconds" do
      {:ok, dt} = DateTime.from_unix(1_700_000_000_123, :millisecond)
      assert Types.serialize(@spec_, dt) == 1_700_000_000_123
    end

    test "validate turns epoch milliseconds back into a DateTime" do
      ms = 1_700_000_000_123
      assert {:ok, %DateTime{} = dt} = Types.validate(@spec_, ms)
      assert DateTime.to_unix(dt, :millisecond) == ms
    end
  end

  describe "direct callbacks" do
    test "wire_spec is an integer primitive" do
      assert UnixMillis.wire_spec() == %{kind: "primitive", type: "integer"}
    end

    test "ts_type is the EpochMillis brand" do
      assert UnixMillis.ts_type() == "EpochMillis"
    end

    test "deserialize accepts an integer and rejects out-of-range values" do
      assert {:ok, %DateTime{}} = UnixMillis.deserialize(0)
      assert {:error, _} = UnixMillis.deserialize(999_999_999_999_999_999)
    end

    test "serialize raises ArgumentError with a helpful message on a non-DateTime" do
      assert_raise ArgumentError, ~r/RpcElixir\.UnixMillis can only serialize a DateTime/, fn ->
        UnixMillis.serialize(:not_a_datetime)
      end

      assert_raise ArgumentError, ~r/RpcElixir\.UnixMillis can only serialize a DateTime/, fn ->
        UnixMillis.serialize(~N[2024-01-15 10:30:00])
      end
    end
  end
end

defmodule RpcElixir.TypesDatetimeDefaultTest do
  use ExUnit.Case, async: true

  alias RpcElixir.Types

  @datetime %{kind: "datetime"}

  test "serialize returns an ISO 8601 string" do
    {:ok, dt} = DateTime.from_unix(1_700_000_000, :second)
    assert Types.serialize(@datetime, dt) == DateTime.to_iso8601(dt)
  end

  test "validate parses an ISO 8601 string into a DateTime" do
    assert {:ok, %DateTime{} = dt} = Types.validate(@datetime, "2023-11-14T22:13:20Z")
    assert DateTime.to_iso8601(dt) == "2023-11-14T22:13:20Z"
  end

  test "validate rejects an integer (no implicit unix-ms coercion)" do
    assert {:error, _} = Types.validate(@datetime, 1_700_000_000_123)
  end

  test "validate rejects a malformed ISO 8601 string" do
    assert {:error, %{"_" => [_]}} = Types.validate(@datetime, "not-a-datetime")
  end
end
