# Custom types

`RpcElixir.CustomType` handles types the library does not know. Implement the
behaviour on any module whose `.t()` you use in specs:

```elixir
@spec create(%{amount: MyApp.Money.t()}, ctx()) :: {:ok, %{result: MyApp.Money.t()}}
```

## Behaviour callbacks

| Callback        | Required | Purpose                                                                                                                       |
| --------------- | -------- | ----------------------------------------------------------------------------------------------------------------------------- |
| `wire_spec/0`   | yes      | Returns an already-resolved internal spec map. That is the shape `RpcElixir.Types.resolve/1` returns. Its inner spec drives the emitted TypeScript. |
| `serialize/1`   | yes      | Takes the Elixir value, returns something JSON-encodable: string, number, boolean, map, list, or nil.                          |
| `deserialize/1` | no       | The input side of `serialize/1`. It takes the wire value, already validated against `wire_spec/0`. It returns `{:ok, domain}` or `{:error, reason}`. Without it, the wire value passes through unchanged. |
| `ts_type/0`     | no       | Emits a branded TypeScript type instead of the plain wire type.                                                               |

```elixir
defmodule MyApp.Money do
  @behaviour RpcElixir.CustomType
  defstruct [:amount, :currency]

  @impl true
  def wire_spec, do: %{kind: "primitive", type: "string"}

  @impl true
  def serialize(%__MODULE__{amount: a, currency: c}), do: "#{a} #{c}"
end
```

## Branded TypeScript types

Implement `ts_type/0` when the client must not auto-parse a string or number
wire. Typical cases: arbitrary-precision numbers, 64-bit ids, epoch-millisecond
timestamps. Codegen then emits a branded alias instead of the bare wire type. A
string wire gives `string & { readonly __brand: "Name" }`. An integer or float
wire gives `number & { readonly __brand: "Name" }`.

Three constraints, all enforced at codegen time:

- `wire_spec/0` must resolve to
  `%{kind: "primitive", type: "string" | "integer" | "float"}`, or codegen raises.
- The name must be a valid TS identifier. It must not clash with a built-in
  brand. Generated struct and procedure interface names also clash. So do
  reserved TypeScript type names. The five built-in brands are listed in
  [Supported types](supported-types.md).
- Two custom types must not share a `ts_type/0`. Codegen raises on the second
  one. The message names the claimed brand.

```elixir
defmodule MyApp.Int64 do
  @behaviour RpcElixir.CustomType

  @impl true
  def wire_spec, do: %{kind: "primitive", type: "string"}

  @impl true
  def serialize(int) when is_integer(int), do: Integer.to_string(int)

  @impl true
  def ts_type, do: "Int64String"
end
```

## Built-in: `RpcElixir.UnixMillis`

A built-in branded-number custom type. A `DateTime` crosses the wire as integer
epoch milliseconds. Its TypeScript type is the `EpochMillis` brand
(`number & { readonly __brand: "EpochMillis" }`). It serializes with
`DateTime.to_unix(dt, :millisecond)`. It deserializes integer milliseconds back
to `{:ok, DateTime.t()} | {:error, atom}`. Use it per field:

```elixir
@spec get_event(input(), ctx()) :: {:ok, %{occurred_at: RpcElixir.UnixMillis.t()}}
```

## `wire_aliases` router option

`wire_aliases` remaps a type across the whole project. You do not annotate every
field. Each `{source, target}` pair maps the source module's `.t()` to a
`RpcElixir.CustomType` target. The source then crosses the wire as that custom
type everywhere. Aliases apply at router compile time, so codegen and runtime
agree.

```elixir
defmodule MyApp.Router do
  use RpcElixir.Router, wire_aliases: [{DateTime, RpcElixir.UnixMillis}]

  scope "events" do
    expose MyApp.Handlers.Events
  end
end
```

Every `DateTime` now serializes as the branded `EpochMillis` number. The target
must implement `RpcElixir.CustomType`. A source cannot alias to itself.

See [Supported types](supported-types.md) for what resolves without a custom
type.
