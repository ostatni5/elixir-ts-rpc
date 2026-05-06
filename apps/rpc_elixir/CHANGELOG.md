# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.0.1] - 2026-06-18

### Added

- `RpcElixir.Context` - request-scoped struct (conn, socket, assigns, private) threaded through middleware and into handlers.
- `RpcElixir.Resolution` - wraps a handler call with its context, arguments, result, and error fields.
- `RpcElixir.Types` - internal type representation and the `internal_spec()` type, plus `CustomType` behaviour for user-defined type mappings.
- `RpcElixir.Types.FromSpec` - recommended backend. Reads classic `@spec` declarations from BEAM debug info via `Code.Typespec` and translates them to the internal type map. No compile-time macro required.
- `RpcElixir.Types.FromInferred` - experimental backend. Reads set-theoretic inferred signatures from the `ExCk` BEAM chunk (Elixir 1.19+, private API, expect breakage on upgrade).
- `RpcElixir.Router` - procedure registration with compile-time `@spec` validation in `__before_compile__`, plus the `wire_aliases` option for router-wide wire type substitution (e.g. `{DateTime, RpcElixir.UnixMillis}`).
- `RpcElixir.Handler` - `use RpcElixir.Handler` captures `@spec` ASTs into a `__rpc_specs__/0` accessor so handlers and router can share a Mix project.
- `RpcElixir.Plug` - HTTP transport for `POST /rpc/*`: JSON decode, dispatch, and response rendering with cookie/header/session draining.
- `RpcElixir.Middleware` (+ `RpcElixir.Middleware.Assign`) - request-scoped middleware framework threaded through `Context`/`Resolution`.
- `RpcElixir.Dispatcher` - pipeline that performs lookup → input validation → handler invocation → output validation → serialization.
- `RpcElixir.RpcError` - structured error struct with `:code`, `:message`, and `:details` fields. The dispatcher promotes typed handler errors and codegen maps them to `RpcError<Code, Details>` in TypeScript.
- `RpcElixir.call/4` - in-process convenience caller for tests and server-to-server invocations.
- TypeScript codegen - the `mix rpc.gen.ts` task and the `:elixir_ts_rpc` compiler emit a fully typed client from a router. A dev `Watcher` regenerates on change.
- Branded wire types - `RpcElixir.CustomType`'s `ts_type/0` callback for branded string and number wires, and `RpcElixir.UnixMillis` (a `DateTime` ↔ epoch-millis `CustomType` dogfooding the public hatch).
- Built-in JSON via Elixir 1.18+'s `JSON` module (no `:jason` dependency). Requires Elixir `~> 1.19`.
- Deterministic codegen output - structs, brands, and middleware error codes are emitted in sorted order so regenerated clients produce byte-stable diffs.

### Notes

- `RpcError.details` values must be JSON-native (strings, numbers, booleans, nil, lists, maps). The built-in `JSON` does not auto-encode `Date`/`DateTime`/`NaiveDateTime`/`Time`/`Decimal`. Pre-stringify any such values before placing them in `details`.

[Unreleased]: https://github.com/ostatni5/elixir-ts-rpc/compare/v0.0.1...HEAD
[0.0.1]: https://github.com/ostatni5/elixir-ts-rpc/releases/tag/v0.0.1
