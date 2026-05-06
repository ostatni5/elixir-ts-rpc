# Supported types

The type system has two surfaces that normalize to the same internal spec
shape (`%{kind: ...}`):

- **Inline shorthand** - passed directly to `RpcElixir.Types.resolve/1`,
  `validate/2`, `serialize/2`.
- **`@spec` typespecs** - read from a compiled module's BEAM debug info by
  `RpcElixir.Types.FromSpec`. Users write `@spec` next to their handlers.
  No compile-time macro captures AST. The internal walker
  (`Types.from_typespec/2`) translates the recovered AST into `%{kind: ...}`
  and supports the typespec forms below.

An experimental third surface, `RpcElixir.Types.FromInferred`, reads
signatures from Elixir's set-theoretic type inference (`ExCk` BEAM chunk).
It bypasses the typespec walker entirely and is lossy by design. See the
module docs for caveats.

## `FromInferred` limitations

The inferred backend translates `Module.Types.Descr` terms directly into the
internal kind shape. It only recognizes a narrow subset. Everything else
collapses to `%{kind: "dynamic"}`. Known gaps versus `FromSpec`:

- **Argument types** - usually `dynamic` unless the function pattern-matches
  or guards on input.
- **Lists (`[T]`, `list(T)`)** - not represented in `Descr` bitmaps. Collapse
  to `dynamic`.
- **`T | nil` (nullable)** - not recovered as `nullable`. Falls through to
  `dynamic`.
- **`{:optional, T}` / optional map keys** - map openness is ignored. All
  known fields look required.
- **Struct types (`%Mod{...}`)** - indistinguishable from plain maps. No
  `:struct` tag is attached.
- **`Date.t()`, `DateTime.t()`, `NaiveDateTime.t()`, `Time.t()`, `Decimal.t()`** -
  seen as generic maps, not as `date` / `datetime` / `decimal`.
- **Ecto schemas (`Mod.t()`)** - not resolved. Only the inferred map shape,
  no field-type derivation.
- **Custom types (`RpcElixir.CustomType`)** - not resolved. `wire_spec/0` is
  never consulted.
- **Atom-literal enums (`:a | :b`)** - recovered as `enum` from `Descr`'s atom
  union (this case works).
- **`integer() | float()` union** - widened to `primitive` / `float`.
- **RPC return `{:ok, T} | {:error, E}`** - inference proves only the
  `{:ok, T}` branch unless the body explicitly returns `{:error, _}`.
  `fetch_rpc/2` reports `{:error, {:invalid_return, _}}` for anything else.
- **Parameterized local types, `any()`, `term()`** - become `dynamic` instead
  of raising.

In practice, `FromInferred` is only useful for handlers whose argument is a
pattern-matched struct/map and whose return is a single `{:ok, T}` tuple over
primitives, atoms, and nested maps. Anything richer should use `FromSpec`.

## Inline shorthand

| Spec                                      | Internal kind                       |
| ----------------------------------------- | ----------------------------------- |
| `:string`                                 | `primitive` / `string`              |
| `:integer`                                | `primitive` / `integer`             |
| `:float`                                  | `primitive` / `float`               |
| `:boolean`                                | `primitive` / `boolean`             |
| `{:optional, t}`                          | `optional`                          |
| `{:nullable, t}`                          | `nullable`                          |
| `{:list, t}`                              | `list`                              |
| `{:stream, t}`                            | `list` (alias)                      |
| `%{key: t, ...}` (plain map)              | `object`                            |
| `%{kind: ...}` (already-resolved)         | passthrough                         |

## From `@spec` typespec AST

| Typespec form                              | Resolved kind                       |
| ------------------------------------------ | ----------------------------------- |
| `String.t()`, `binary()`                   | `primitive` / `string`              |
| `integer()`, `non_neg_integer()`, `pos_integer()` | `primitive` / `integer`      |
| `float()`, `number()`                      | `primitive` / `float`               |
| `boolean()`                                | `primitive` / `boolean`             |
| `Date.t()`                                 | `date`                              |
| `DateTime.t()`                             | `datetime`                          |
| `NaiveDateTime.t()`                        | `naive_datetime`                    |
| `Time.t()`                                 | `time`                              |
| `Decimal.t()`                              | `decimal`                           |
| `[T]`, `list(T)`                           | `list`                              |
| `T \| nil`                                 | `nullable`                          |
| `:foo \| :bar \| :baz`                     | `enum` (atom-literal union)         |
| `:foo` (single literal)                    | `enum` with one value               |
| `%{key: T, ...}`                           | `object` (all required)             |
| `%{required(:k) => T}`                     | `object` field (required)           |
| `%{optional(:k) => T}`                     | `object` field (optional)           |
| `%Mod{field: T, ...}`                      | `object` with `:struct => Mod`      |
| `Mod.t()` where `Mod` defines `@type t`    | resolved from `@type t`             |
| `Mod.t()` where `Mod` is an Ecto schema    | derived from `__schema__/1`         |
| `Mod.t()` where `Mod` implements `RpcElixir.CustomType` | `custom`               |
| `local_alias(T)`                           | expanded from local `@type` (parameterized) |

### Ecto field type mapping

When `Mod.t()` resolves to an Ecto schema, fields are derived from
`module.__schema__(:type, name)`:

| Ecto type                                    | Resolved kind                  |
| -------------------------------------------- | ------------------------------ |
| `:string`, `:binary_id`                      | `primitive` / `string`         |
| `:id`, `:integer`                            | `primitive` / `integer`        |
| `:float`                                     | `primitive` / `float`          |
| `:boolean`                                   | `primitive` / `boolean`        |
| `:date`                                      | `date`                         |
| `:utc_datetime`, `:utc_datetime_usec`        | `datetime`                     |
| `:naive_datetime`, `:naive_datetime_usec`    | `naive_datetime`               |
| `:time`                                      | `time`                         |
| `:decimal`                                   | `decimal`                      |
| `{:array, T}`                                | `list` of T                    |
| `:map`                                       | rejected - use embedded schema or explicit `%{...}` |

## Explicitly rejected (with actionable errors)

- `any()`, `term()` - every field must have an explicit type.
- `map()` - use an explicit map shape like `%{key: T, ...}`.
- `atom()` - use a literal atom or atom-literal union for enums.
- Non-atom non-nullable unions (e.g. `String.t() | integer()`).

## Error details

Typed errors carry a `:message` and optional extra detail fields (see the
[Errors section of the library README](../README.md#errors)). Two caveats apply
to what you put there:

- **Sent to the client verbatim.** Everything in a typed error's `:message` and
  detail fields is serialized to the client as-is. This is **not** gated by the
  `:expose_error_details` config. That flag only redacts the framework-generated
  diagnostics on the unexpected-return / raised-exception paths. Never put
  internal diagnostics (stack traces, SQL, secrets) in a typed error's
  `:message`/`:details`. Treat both as client-facing.
- **`details` values must be JSON-native.** Errors are serialized with Elixir
  1.18+'s built-in `JSON` module, which does not auto-encode `Date`, `DateTime`,
  `NaiveDateTime`, `Time`, or `Decimal`. Putting any of those in `details`
  **raises at serialization time**, a runtime failure on the error path, not a
  compile-time check. Pre-convert to strings or numbers first.

```elixir
# bad - raises at runtime
{:error, %{code: :expired, details: %{at: ~U[2026-01-01 00:00:00Z]}}}

# good
{:error, %{code: :expired, details: %{at: DateTime.to_iso8601(~U[2026-01-01 00:00:00Z])}}}
```

On the TypeScript side, the generated `RpcError.details` type reflects the
declared detail fields but is best-effort: at runtime `details` may be
`undefined` (framework-level errors carry no domain details), so guard access
with `e.details?.field`.

## Custom types

Implement `RpcElixir.CustomType` on any module to make `Mod.t()` valid in
specs. The behaviour requires `wire_spec/0` (the resolved internal spec for
the wire format) and `serialize/1` (turn a value into something JSON-encodable).

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

### Branded TS types

Implement the optional `ts_type/0` callback to emit a branded TypeScript type
instead of the plain wire type. The brand keeps callers from accidentally
treating the wire value as an untagged primitive. Branding works for both
string and number wires. Codegen emits `string & { __brand }` or
`number & { __brand }` respectively, so `wire_spec/0` must resolve to
`%{kind: "primitive", type: "string" | "integer" | "float"}`.

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

### Built-in: `RpcElixir.UnixMillis` / `EpochMillis`

`RpcElixir.UnixMillis` is a built-in branded-number custom type. It
serializes a `DateTime` as epoch milliseconds (integer wire) and emits the
TypeScript brand `EpochMillis` (`number & { __brand }`), preventing callers
from passing a bare number where a timestamp is expected.

**Per-field** - annotate individual spec fields with `RpcElixir.UnixMillis.t()`:

```elixir
@spec get_event(input(), ctx()) :: {:ok, %{occurred_at: RpcElixir.UnixMillis.t()}}
```

**Project-wide via `wire_aliases`** - use the `wire_aliases` router option to
remap every `DateTime` in the router without per-field annotation. Aliases are
applied at compile time, so codegen and runtime serialization agree
automatically.

```elixir
defmodule MyApp.Router do
  use RpcElixir.Router, wire_aliases: [{DateTime, RpcElixir.UnixMillis}]

  procedure "events.get", &MyApp.Handlers.Events.get/2
end
```

Each `{source, target}` pair in `wire_aliases` maps the source module's `.t()`
to a `RpcElixir.CustomType` target. The target must implement the
`RpcElixir.CustomType` behaviour.
