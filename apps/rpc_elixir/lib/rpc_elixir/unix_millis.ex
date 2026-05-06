defmodule RpcElixir.UnixMillis do
  @moduledoc """
  Built-in branded-number custom type: a `DateTime` crossing the wire as epoch
  milliseconds. Emits the TypeScript brand `EpochMillis`
  (a `number & { readonly __brand: "EpochMillis" }`), so callers can't
  accidentally pass a bare number where an instant is expected.

  Use per-field as `RpcElixir.UnixMillis.t()`, or map every `DateTime` in a router
  to it via `use RpcElixir.Router, wire_aliases: [{DateTime, RpcElixir.UnixMillis}]`.
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
