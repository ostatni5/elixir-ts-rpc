# Supported types

You write ordinary Elixir types. Codegen resolves each one to an internal
**kind** (`%{kind: ...}`). The TypeScript then follows from the kind. `integer`
and `float` both become `number`. `nullable` becomes `T | null`. The tables
below give the resolved kind, not the emitted TypeScript.

Two surfaces, same kinds:

- **Inline shorthand**, passed to `RpcElixir.Types.resolve/1`, `validate/2`, or
  `serialize/2`.
- **`@spec` typespecs**. `RpcElixir.Types.FromSpec` reads them from BEAM debug
  info via `Code.Typespec`. No type macro is needed. `use RpcElixir.Handler` can
  also capture the AST at compile time.

`RpcElixir.Types.FromInferred` is an experimental third surface. It is lossy and
not recommended. See its module docs.

## Inline shorthand

| Spec                              | Internal kind           |
| --------------------------------- | ----------------------- |
| `:string`                         | `primitive` / `string`  |
| `:integer`                        | `primitive` / `integer` |
| `:float`                          | `primitive` / `float`   |
| `:boolean`                        | `primitive` / `boolean` |
| `{:optional, t}`                  | `optional`              |
| `{:nullable, t}`                  | `nullable`              |
| `{:list, t}`                      | `list`                  |
| `{:stream, t}`                    | `list` (alias)          |
| `%{key: t, ...}` (plain map)      | `object`                |
| `%{kind: ...}` (already-resolved) | passthrough             |

## From `@spec` typespec AST

| Typespec form                                           | Resolved kind                               |
| ------------------------------------------------------- | ------------------------------------------- |
| `String.t()`, `binary()`                                | `primitive` / `string`                      |
| `integer()`, `non_neg_integer()`, `pos_integer()`       | `primitive` / `integer`                     |
| `float()`, `number()`                                   | `primitive` / `float`                       |
| `boolean()`                                             | `primitive` / `boolean`                     |
| `Date.t()`                                              | `date`                                      |
| `DateTime.t()`                                          | `datetime`                                  |
| `NaiveDateTime.t()`                                     | `naive_datetime`                            |
| `Time.t()`                                              | `time`                                      |
| `Decimal.t()`                                           | `decimal`                                   |
| `[T]`, `list(T)`                                        | `list`                                      |
| `T \| nil`                                              | `nullable`                                  |
| `:foo \| :bar \| :baz`                                  | `enum` (atom-literal union)                 |
| `:foo` (single literal)                                 | `enum` with one value                       |
| `%{key: T, ...}`                                        | `object` (all required)                     |
| `%{required(:k) => T}`                                  | `object` field (required)                   |
| `%{optional(:k) => T}`                                  | `object` field (optional)                   |
| `%Mod{field: T, ...}`                                   | `object` with `:struct => Mod`              |
| `Mod.t()` where `Mod` defines `@type t`                 | resolved from `@type t`                     |
| `Mod.t()` where `Mod` is an Ecto schema                 | derived from `__schema__/1`                 |
| `Mod.t()` where `Mod` implements `RpcElixir.CustomType` | `custom`                                    |
| `local_alias(T)`                                        | expanded from local `@type` (parameterized) |

Recursive struct types are supported. Self-referential and mutually recursive
ones both work. The cycle point becomes a named interface reference. A
non-struct recursive type raises.

The `custom` kind, branded wire types, and project-wide `wire_aliases` live in
[Custom types](custom-types.md).

### Ecto field type mapping

Each field of an Ecto schema comes from `module.__schema__(:type, name)`.
Temporal and decimal fields check `wire_aliases` first. Take
`wire_aliases: [{DateTime, RpcElixir.UnixMillis}]`. A `:utc_datetime` field then
becomes that custom type. It is no longer the plain `datetime` kind. See
[Custom types](custom-types.md).

| Ecto type                                 | Resolved kind                                       |
| ----------------------------------------- | --------------------------------------------------- |
| `:string`, `:binary_id`                   | `primitive` / `string`                              |
| `:id`, `:integer`                         | `primitive` / `integer`                             |
| `:float`                                  | `primitive` / `float`                               |
| `:boolean`                                | `primitive` / `boolean`                             |
| `:date`                                   | `date`                                              |
| `:utc_datetime`, `:utc_datetime_usec`     | `datetime`                                          |
| `:naive_datetime`, `:naive_datetime_usec` | `naive_datetime`                                    |
| `:time`                                   | `time`                                              |
| `:decimal`                                | `decimal`                                           |
| `{:array, T}`                             | `list` of T                                         |
| `:map`                                    | rejected; use an embedded schema or explicit `%{}`  |

## Built-in brand names

Five kinds do not emit a plain `string`. Each emits a branded alias. The shape
is `string & { readonly __brand: "Name" }`. A brand blocks mixing it with any
string.

| Kind             | TypeScript brand      | Base type |
| ---------------- | --------------------- | --------- |
| `date`           | `DateString`          | `string`  |
| `datetime`       | `DateTimeString`      | `string`  |
| `naive_datetime` | `NaiveDateTimeString` | `string`  |
| `time`           | `ISOTime`             | `string`  |
| `decimal`        | `DecimalString`       | `string`  |

A custom type can emit its own brand. Those names must not clash with these
five. See [Custom types](custom-types.md).

## `PaginatedResponse<T>`

One object shape is special-cased. These exact three fields are detected:

```elixir
%{items: [T], next_cursor: String.t() | nil, has_more: boolean()}
```

Codegen emits a shared generic type. An inline object type is not used:

```ts
export type PaginatedResponse<T> = { items: T[]; next_cursor: string | null; has_more: boolean };

// a procedure output of that shape renders as:
PaginatedResponse<User>
```

The match is exact. `next_cursor` must be a nullable string. `has_more` must be
a boolean. A fourth field breaks the match. So does a different field type.

## Objects are closed

An object rejects any field the spec omits. Each extra field gives an
`"unexpected field"` error. On input that means `input_validation_failed`,
status 400. On output it means `output_validation_failed`, status 500. Declare
the field, or mark it optional. Or stop sending it.

## Coercions during validation

Validation converts a few wire forms:

- An integer is accepted for a `float` field. It widens to a float.
- ISO 8601 strings parse into dates and times. That covers `Date`, `DateTime`,
  `NaiveDateTime`, and `Time`.
- A decimal string parses into a `Decimal`.
- An enum string becomes an atom. Only an existing atom is accepted.

## Explicitly rejected

These raise an error. They do not degrade silently.

| Type                                             | Use instead                          |
| ------------------------------------------------ | ------------------------------------ |
| `any()`, `term()`                                | an explicit type for every field     |
| `map()`                                          | an explicit shape, `%{key: T, ...}`  |
| `atom()`                                         | a literal atom or atom-literal union |
| non-atom non-nullable unions (`String.t() \| integer()`) | one concrete type            |

`atom()` has no clause of its own. Its error asks for a local `@type`. That
message is misleading. Use a literal atom or an atom union.
