defmodule BasicServer.Types.Int64 do
  @moduledoc """
  A 64-bit integer id.

  Sent over the wire as a string because JavaScript's `number` is only safe up
  to 2^53−1 — a raw 64-bit id would silently lose precision once coerced to a
  JS number. Implementing `ts_type/0` makes the generated client expose this as
  the branded `Int64String` type with no automatic coercion, forcing the caller
  to parse it deliberately (e.g. with `BigInt`).
  """

  @behaviour RpcElixir.CustomType

  @type t :: integer()

  @impl RpcElixir.CustomType
  def wire_spec, do: %{kind: "primitive", type: "string"}

  @impl RpcElixir.CustomType
  def serialize(int) when is_integer(int), do: Integer.to_string(int)

  @impl RpcElixir.CustomType
  def ts_type, do: "Int64String"
end
