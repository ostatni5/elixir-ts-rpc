defmodule RpcElixir.CustomType do
  @moduledoc """
  Teaches the library about a type it does not know.

  Implement it on any module whose `.t()` appears in a spec. Then use
  `Mod.t()` in your specs as normal:

      @spec create(%{amount: MyApp.Money.t()}, ctx()) :: {:ok, %{result: MyApp.Money.t()}}

  `c:wire_spec/0` and `c:serialize/1` are required. `c:deserialize/1` and
  `c:ts_type/0` are optional.

  See [Custom types](custom-types.md) for worked examples, branded TypeScript
  types, `RpcElixir.UnixMillis`, and `wire_aliases`.
  """

  @doc """
  Required. Returns an already-resolved internal spec map.

  That is the same shape `RpcElixir.Types.resolve/1` returns. The inner spec
  decides the TypeScript that codegen emits.
  """
  @callback wire_spec() :: RpcElixir.Types.internal_spec()

  @doc """
  Required. Receives the Elixir value.

  It must return a value that conforms to `c:wire_spec/0`. The result is
  serialized again against that spec. For a primitive wire that is a string,
  number, boolean, or nil. A structured wire raises on a mismatch, such as a
  missing required field.
  """
  @callback serialize(value :: term()) :: term()

  @doc """
  Optional. The input side of `c:serialize/1`.

  It receives the wire value, already validated against `c:wire_spec/0`. It
  returns `{:ok, domain_value}`, or `{:error, reason}` to reject bad input.
  When not implemented, the wire-validated value passes through unchanged.
  """
  @callback deserialize(wire :: term()) :: {:ok, term()} | {:error, term()}

  @doc """
  Optional. Emits a branded TypeScript alias instead of the plain wire type.

  Implement it when the client must not auto-parse a string or number wire.
  For example: arbitrary-precision numbers, 64-bit ids, or epoch-millisecond
  timestamps. A string wire gives `string & { readonly __brand: "Name" }`. An
  integer or float wire gives `number & { readonly __brand: "Name" }`.

  This requires `c:wire_spec/0` to resolve to
  `%{kind: "primitive", type: "string" | "integer" | "float"}`. Any other wire
  shape would make the brand lie about its base type. Codegen raises.

  The returned name must be a valid TypeScript identifier. It must not clash
  with a built-in brand, a generated interface, or a reserved TypeScript type
  name. No two custom types may return the same name.
  """
  @callback ts_type() :: String.t()

  @optional_callbacks deserialize: 1, ts_type: 0
end
