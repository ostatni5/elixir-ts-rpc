defmodule RpcElixir.UnixMillis do
  @moduledoc """
  Built-in branded-number custom type. A `DateTime` crosses the wire as epoch
  milliseconds. The emitted TypeScript brand is `EpochMillis`
  (`number & { readonly __brand: "EpochMillis" }`). It stops callers passing a
  bare number where an instant is expected.

  Use it per field as `RpcElixir.UnixMillis.t()`. Or map every `DateTime` in a
  router with `wire_aliases`, see [Custom types](custom-types.md).
  """
  @behaviour RpcElixir.CustomType

  @type t :: DateTime.t()

  @doc "Wire format: a JSON integer (epoch milliseconds)."
  @impl true
  def wire_spec, do: %{kind: "primitive", type: "integer"}

  @doc "Serializes a `DateTime` to integer epoch milliseconds."
  @impl true
  def serialize(%DateTime{} = dt), do: DateTime.to_unix(dt, :millisecond)

  def serialize(other),
    do:
      raise(
        ArgumentError,
        "RpcElixir.UnixMillis can only serialize a DateTime, got: #{inspect(other)}"
      )

  @doc "Deserializes integer epoch milliseconds to `{:ok, DateTime.t()} | {:error, atom}`."
  @impl true
  def deserialize(ms) when is_integer(ms), do: DateTime.from_unix(ms, :millisecond)

  @doc "TypeScript brand name emitted for this type."
  @impl true
  def ts_type, do: "EpochMillis"
end
