defmodule RpcElixir.CustomType do
  @moduledoc """
  Escape hatch for teaching elixir-ts-rpc how to handle custom or third-party types.

  Implement this behaviour on any module whose `.t()` you want to use in
  procedure specs but that the library doesn't know about:

      defmodule MyApp.Money do
        @behaviour RpcElixir.CustomType

        @impl RpcElixir.CustomType
        def wire_spec, do: %{kind: "primitive", type: "string"}

        @impl RpcElixir.CustomType
        def serialize(%__MODULE__{amount: a, currency: c}), do: "\#{a} \#{c}"
      end

  Then use it in specs as normal:

      @spec create(input :: %{amount: MyApp.Money.t()}) :: {:ok, %{result: MyApp.Money.t()}}

  `wire_spec/0` must return an already-resolved internal spec map, the same
  shape that `RpcElixir.Types.resolve/1` returns. The inner spec determines the
  TypeScript type that the codegen emits.

  `serialize/1` receives the Elixir value and must return something that can
  be JSON-encoded (a string, number, boolean, map, list, or nil).

  The optional `deserialize/1` callback is the input dual of `serialize/1`: it
  receives the wire value (already validated against `wire_spec/0`) and returns
  `{:ok, domain_value}` on success or `{:error, reason}` to reject malformed
  input. When absent, the wire-validated value passes through unchanged.

  ## Branded TS types (precision-honest)

  When the wire format is a string or number that the client must NOT auto-parse
  (e.g. arbitrary-precision numbers, 64-bit ids, epoch-millisecond timestamps),
  implement the optional `c:ts_type/0` callback. The codegen will emit a branded TS
  type alias instead of the inner wire type, forcing callers to choose their own
  parser:

      defmodule MyApp.Int64 do
        @behaviour RpcElixir.CustomType

        @impl RpcElixir.CustomType
        def wire_spec, do: %{kind: "primitive", type: "string"}

        @impl RpcElixir.CustomType
        def serialize(int) when is_integer(int), do: Integer.to_string(int)

        @impl RpcElixir.CustomType
        def ts_type, do: "Int64String"
      end

  Branded aliases are emitted as `string & { readonly __brand: "Name" }` for a
  string wire or `number & { readonly __brand: "Name" }` for an integer/float
  wire (where `Name` is the `c:ts_type/0` value), so `c:ts_type/0` requires
  `wire_spec/0` to resolve to `%{kind: "primitive", type: "string" | "integer" | "float"}`
  because any other wire shape would make the brand lie about its base type, and the
  codegen raises. The returned name must be a valid TS identifier and must not
  collide with a built-in brand, a generated interface, or a reserved TypeScript
  type name.

  ## Built-in custom types and router aliases

  `RpcElixir.UnixMillis` ships as a branded number custom type: a `DateTime`
  serialized as epoch milliseconds, typed in TypeScript as the `EpochMillis`
  brand. Use it per-field as `RpcElixir.UnixMillis.t()`, or remap every
  `DateTime` in a router at once with the `wire_aliases` option:

      use RpcElixir.Router, wire_aliases: [{DateTime, RpcElixir.UnixMillis}]

  Each `{source, target}` pair maps a source module's `.t()` to a `CustomType`
  target. The alias is applied at compile time to both serialization and type
  generation.
  """

  @callback wire_spec() :: RpcElixir.Types.internal_spec()
  @callback serialize(value :: term()) :: term()
  @callback deserialize(wire :: term()) :: {:ok, term()} | {:error, term()}
  @callback ts_type() :: String.t()

  @optional_callbacks deserialize: 1, ts_type: 0
end
