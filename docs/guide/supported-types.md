# Supported types

You write ordinary `@spec` typespecs. The codegen resolves them to TypeScript.
This page covers the most common mappings. The **full reference** is maintained
alongside the library. It covers inline shorthand, `FromInferred` limitations,
Ecto field mapping, rejected types, and error-detail rules.

[Full type reference →](https://github.com/ostatni5/elixir-ts-rpc/blob/main/apps/rpc_elixir/docs/supported-types.md)

## Common `@spec` mappings

The right column is the internal **kind** the resolver produces, not the final
TypeScript type. The emitted TS follows from the kind. For example, `integer` and
`float` both become `number`, and `nullable` becomes `T | null`.

| Typespec form                                     | Resolved kind (internal) |
| ------------------------------------------------- | ------------------------ |
| `String.t()`, `binary()`                          | `string`                 |
| `integer()`, `non_neg_integer()`, `pos_integer()` | `integer`                |
| `float()`, `number()`                             | `float`                  |
| `boolean()`                                       | `boolean`                |
| `Date.t()`                                        | `date`                   |
| `DateTime.t()`                                    | `datetime`               |
| `NaiveDateTime.t()`                               | `naive_datetime`         |
| `Time.t()`                                        | `time`                   |
| `Decimal.t()`                                     | `decimal`                |
| `[T]`, `list(T)`                                  | `list`                   |
| `T \| nil`                                        | `nullable`               |
| `:foo \| :bar \| :baz`                            | `enum` (atom union)      |
| `%{key: T, ...}`                                  | `object` (all required)  |
| `%{optional(:k) => T}`                            | `object` field, optional |
| `%Mod{field: T, ...}`                             | `object` with struct tag |
| `Mod.t()` (Ecto schema)                           | derived from schema      |
| `Mod.t()` (`RpcElixir.CustomType`)                | `custom` wire type       |

## Explicitly rejected

These raise with an actionable error rather than silently degrading. Every
field must carry a concrete type.

- `any()`, `term()`
- `map()`: use an explicit shape like `%{key: T, ...}`
- `atom()`: use a literal atom or atom-literal union for enums
- Non-atom non-nullable unions (e.g. `String.t() | integer()`)

## Custom & branded wire types

`CustomType` with `ts_type/0`, branded string/number wires,
`RpcElixir.UnixMillis`, and the `wire_aliases` router option let you control how
a value crosses the wire. For example, you can send `DateTime.t()` as
epoch-millis everywhere. See the [full reference](https://github.com/ostatni5/elixir-ts-rpc/blob/main/apps/rpc_elixir/docs/supported-types.md)
for details.
