# Handling errors

Handler errors are typed. The `@spec` declares the shape.
`RpcElixir.Dispatcher` promotes the runtime value to an `RpcElixir.RpcError`. The
client throws a catchable `RpcError`. You tell the cases apart by `code`.

## Supported error shapes

Use a bare atom union. Or use a map with `:code`, plus optional `:message` and
detail fields. The `:code` value must be an atom. A string is not recognised.
So `%{code: "not_found"}` becomes `:handler_error`, status 500.

```elixir
# 1. Bare atom union.
@spec get(input(), ctx()) :: {:ok, user()} | {:error, :not_found | :forbidden}
def get(_, _), do: {:error, :not_found}

# 2. Map with :code, optional :message, and extra detail fields.
@spec update(input(), ctx()) ::
        {:ok, user()}
        | {:error, %{code: :not_found | :email_taken, message: String.t(), field: String.t() | nil}}
def update(_, _), do: {:error, %{code: :email_taken, message: "in use", field: "email"}}
```

Anything else is a framework bug. A valid error return is an atom, an
`%RpcError{}`, or a map with an atom `:code`. Other returns come back as
`:handler_error` with status 500. That covers
`{:error, {:bobo, :gaga}}`, `{:error, [code: :foo]}`, and
`{:error, "string"}`. The original value is `inspect`-ed into `details.reason`.
That reaches the client. `:expose_error_details` does not gate it.

Error returns are never validated. Only input and output are. The declared
`error` type drives codegen only. So a handler can return an undeclared code.
The client's typed narrowing then misses it.

## Wire format

The dispatcher stamps `source`. It lifts `:code` and `:message` to the top of
the JSON envelope. Everything else goes under `details`:

```elixir
{:error, %{code: :email_taken, message: "in use", field: "email"}}
```

```json
HTTP 400
{"error": {"code": "email_taken", "source": "domain", "message": "in use", "details": {"field": "email"}}}
```

## Generated TypeScript

Each procedure gets a `DomainError` alias over its declared codes. The details
arm is widened by `| undefined`.

```ts
import { DomainError, MiddlewareError } from "@elixir-ts-rpc/client";

export type UsersUpdateError = DomainError<
  "not_found" | "email_taken",
  { field: string | null } | undefined
>;
```

The full error type also unions any middleware arms the procedure can hit. For
example: `UsersUpdateError | MiddlewareError<"unauthorized">`. Read details with
`err.details?.field`. At runtime `details` may be `undefined`. See
[Using the client](https://ostatni5.github.io/elixir-ts-rpc/guide/client) for the
narrowing guards.

## Status codes

A typed error's status comes from its `code`:

- `:not_found` gives 404.
- A code with the same name as a framework code takes that status. So
  `:unauthorized` gives 401 and `:forbidden` gives 403.
- Anything else gives 400.
- Return `%RpcError{status: 422}` to set the status yourself.

Framework-emitted errors carry their own status. See
`RpcElixir.RpcError.framework_errors/0`:

| Framework code             | Status |
| -------------------------- | ------ |
| `procedure_not_found`      | 404    |
| `input_validation_failed`  | 400    |
| `output_validation_failed` | 500    |
| `handler_error`            | 500    |
| `middleware_halted`        | 500    |
| `unauthorized`             | 401    |
| `forbidden`                | 403    |
| `payload_too_large`        | 413    |
| `unsupported_media_type`   | 415    |

## Two rules for what you put in an error

**`:message` and detail fields reach the client word for word.** Never put
internal diagnostics in them: stack traces, SQL, secrets.
`:expose_error_details` does not gate this. The flag defaults to `false`. It
redacts two of three `:handler_error` paths. Those two are an unexpected return
and a raised exception. The third path is never redacted. An unrecognised error
return always sends `details.reason`. The `inspect`-ed value goes out either
way. So keep internal data out of every error return.

**`details` values must be JSON-native.** Errors serialize with Elixir's built-in
`JSON` module. It does not auto-encode `Date`, `DateTime`, `NaiveDateTime`,
`Time`, or `Decimal`. Any of those in `details` raises during serialization.
That is a runtime failure, not a compile-time check. Convert them first:

```elixir
# raises at runtime
{:error, %{code: :expired, at: ~U[2026-01-01 00:00:00Z]}}

# correct
{:error, %{code: :expired, at: DateTime.to_iso8601(~U[2026-01-01 00:00:00Z])}}
```

See [Supported types](supported-types.md) for the `@spec` to TypeScript mapping.
