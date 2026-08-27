# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.0.2] - 2026-08-26

### Added

- Elixir 1.17 and 1.18 support: the requirement drops from `~> 1.19` to `~> 1.17`. Elixir 1.17 predates the built-in `JSON` module, so consumers on that version add `{:jason, "~> 1.4"}` to their own deps. The backend is resolved at compile time, so call sites pay nothing for the indirection.
- `@elixir-ts-rpc/react` — a TanStack Query adapter for the generated client. Typed `useQuery`, `useSuspenseQuery` and `useMutation` per procedure, infinite queries, a `queryKeyPrefix` option, `queryFilter`/`skipToken` helpers, and the `RpcInputOf`/`RpcOutputOf`/`RpcErrorOf` type helpers.
- `@elixir-ts-rpc/client` now exports the surface a framework adapter needs: `isRpcMethod`, `AnyRpcMethod`, `deriveKey` and `buildProxy`. `@elixir-ts-rpc/react` is built entirely on these, so another adapter can be too.
- A documentation site with type-on-hover on every snippet, checked against real codegen output, and a browser playground that runs the actual Elixir codegen compiled to WebAssembly. Links are in the package metadata.

### Changed

- `RpcElixir.Types.FromInferred` requires Elixir 1.19 or later and now says so. Below 1.19 every lookup returns `{:error, :no_signature}` rather than relying on the library's own version floor. `RpcElixir.Types.FromSpec` remains the recommended backend on all supported versions.
- Codegen no longer uses `:re` or selects over the module definition table, so it runs on AtomVM. The TypeScript identifier check in `emit_prop_key/1` is hand-rolled and slightly stricter than the regex it replaces: Erlang's `re` let `$` match before a trailing newline, and a key ending in a newline is now quoted rather than emitted bare. `RpcElixir.Handler` asks `Module.defines?/3` per function instead of building a `MapSet` from `Module.definitions_in/2`.
- Substantially expanded and corrected documentation across every public module, plus dedicated guide pages for custom types, error handling, middleware and plug options.

### Fixed

- Compiling the library emitted two `FileSystem.start_link/1 is undefined` warnings in any project without the optional `:file_system` dependency, which is most of them. `rpc.gen.ts.watch` references `FileSystem` directly, and the library's own build always has the dep, so the warnings only ever appeared downstream. The reference is now marked `@compile {:no_warn_undefined, FileSystem}`. The runtime check that tells you to add the dep is unchanged.
- Middleware-declared error codes could silently vanish from the generated client. `middleware_error_codes/1` used `function_exported?/3`, which only answers for already-loaded modules, so whether a middleware's codes reached the generated types depended on what else happened to load first. The module is now loaded before it is asked.

## [0.0.1] - 2026-06-18

### Added

- `RpcElixir.Context` — request-scoped struct (conn, socket, assigns, private) threaded through middleware and into handlers.
- `RpcElixir.Resolution` — wraps a handler call with its context, arguments, result, and error fields.
- `RpcElixir.Types` — internal type representation and the `internal_spec()` type, plus `CustomType` behaviour for user-defined type mappings.
- `RpcElixir.Types.FromSpec` — recommended backend; reads classic `@spec` declarations from BEAM debug info via `Code.Typespec` and translates them to the internal type map. No compile-time macro required.
- `RpcElixir.Types.FromInferred` — experimental backend; reads set-theoretic inferred signatures from the `ExCk` BEAM chunk (Elixir 1.19+, private API, expect breakage on upgrade).
- `RpcElixir.Router` — procedure registration with compile-time `@spec` validation in `__before_compile__`, plus the `wire_aliases` option for router-wide wire type substitution (e.g. `{DateTime, RpcElixir.UnixMillis}`).
- `RpcElixir.Handler` — `use RpcElixir.Handler` captures `@spec` ASTs into a `__rpc_specs__/0` accessor so handlers and router can share a Mix project.
- `RpcElixir.Plug` — HTTP transport for `POST /rpc/*`: JSON decode, dispatch, and response rendering with cookie/header/session draining.
- `RpcElixir.Middleware` (+ `RpcElixir.Middleware.Assign`) — request-scoped middleware framework threaded through `Context`/`Resolution`.
- `RpcElixir.Dispatcher` — pipeline that performs lookup → input validation → handler invocation → output validation → serialization.
- `RpcElixir.RpcError` — structured error struct with `:code`, `:message`, and `:details` fields; the dispatcher promotes typed handler errors and codegen maps them to a typed `DomainError<Code, Details>` alias in TypeScript.
- `RpcElixir.call/4` — in-process convenience caller for tests and server-to-server invocations.
- TypeScript codegen — the `mix rpc.gen.ts` task and the `:elixir_ts_rpc` compiler emit a fully typed client from a router; a dev `Watcher` regenerates on change. Each generated method carries a JSDoc link to the handler line that produced it, as an absolute `file://` URI editors can open.
- Branded wire types — `RpcElixir.CustomType`'s `ts_type/0` callback for branded string and number wires, and `RpcElixir.UnixMillis` (a `DateTime` ↔ epoch-millis `CustomType` dogfooding the public hatch).
- Built-in JSON via Elixir 1.18+'s `JSON` module (no `:jason` dependency). Requires Elixir `~> 1.19`.
- Deterministic codegen output — structs, brands, and middleware error codes are emitted in sorted order so regenerated clients produce byte-stable diffs.

### Notes

- `RpcError.details` values must be JSON-native (strings, numbers, booleans, nil, lists, maps). The built-in `JSON` does not auto-encode `Date`/`DateTime`/`NaiveDateTime`/`Time`/`Decimal`; pre-stringify any such values before placing them in `details`.

[Unreleased]: https://github.com/ostatni5/elixir-ts-rpc/compare/0.0.2...HEAD
[0.0.2]: https://github.com/ostatni5/elixir-ts-rpc/compare/0.0.1...0.0.2
[0.0.1]: https://github.com/ostatni5/elixir-ts-rpc/releases/tag/0.0.1
