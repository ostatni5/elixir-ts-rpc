import { combineSignals } from "./abort.js";
import {
  type DomainError,
  type FrameworkError,
  type MiddlewareError,
  RpcError,
  TRANSPORT_ERROR_CODES,
  type TransportError,
} from "./errors.js";
import { doFetch } from "./fetch.js";
import { chainInterceptors, type RpcInterceptor, type RpcRequest } from "./interceptor.js";

export type {
  DomainError,
  FrameworkError,
  MiddlewareError,
  RpcErrorPayload,
  RpcErrorSource,
  TransportError,
  TransportErrorCode,
} from "./errors.js";
export type { RpcInterceptor, RpcRequest, RpcResponse, RpcUnary } from "./interceptor.js";
export { RpcError, TRANSPORT_ERROR_CODES };

/**
 * Narrows `unknown` to {@link RpcError} via `instanceof` — the only narrowing
 * the runtime can verify. `code` stays `string` (it includes client-synthesized
 * `network_error`/`transport_error`/`aborted`; see `fetch.ts`), so callers
 * should `switch (e.code)` with a `default` rather than assume a domain union.
 */
export function isRpcError(e: unknown): e is RpcError {
  return e instanceof RpcError;
}

/**
 * Narrows to a {@link TransportError} — an {@link RpcError} carrying one of the
 * client-synthesized {@link TRANSPORT_ERROR_CODES} (`aborted`/`network_error`/
 * `transport_error`). Unlike {@link isRpcError}, this gives a literal `code`
 * union, so a transport-only handler can `switch (e.code)` exhaustively. Server
 * domain errors are left to a procedure's own `isError` guard.
 */
export function isTransportError(e: unknown): e is TransportError {
  return e instanceof RpcError && (TRANSPORT_ERROR_CODES as readonly string[]).includes(e.code);
}

// When `e` is statically a procedure's generated error union
// (`DomainError<…> | MiddlewareError<…>`), narrow to just the arm matching the
// source guard via `Extract`; when no arm matches (a plain `RpcError`, or
// `unknown` from a `catch`) fall back to `T & E`. Both branches are subsets of
// `T`, so the predicate stays assignable to `e`. The `[…]` tuple stops the
// conditional from distributing so `Extract` sees the whole union at once.
type NarrowToSource<T, E> = [Extract<T, E>] extends [never] ? T & E : Extract<T, E>;

/**
 * Narrows to a domain error — an {@link RpcError} a handler returned as part of
 * its `{:error, ...}` contract (`source: "domain"`). These are the errors a
 * caller branches on in business logic. On a generated procedure error union it
 * narrows `code`/`details` to the domain arm at compile time.
 */
export function isDomainError<T>(e: T): e is NarrowToSource<T, DomainError> {
  return e instanceof RpcError && e.source === "domain";
}

/**
 * Narrows to a middleware error — an {@link RpcError} produced by a server
 * middleware halt (`source: "middleware"`), e.g. auth. Typically handled
 * cross-cuttingly (redirect to login) rather than per-procedure. On a generated
 * procedure error union it narrows to the middleware arm at compile time.
 */
export function isMiddlewareError<T>(e: T): e is NarrowToSource<T, MiddlewareError> {
  return e instanceof RpcError && e.source === "middleware";
}

/**
 * Narrows to a framework error — an {@link RpcError} from the server's
 * protocol/validation layer (`source: "framework"`), e.g. `procedure_not_found`
 * or `input_validation_failed`. Usually a bug or infra issue: handle generically.
 */
export function isFrameworkError<T>(e: T): e is NarrowToSource<T, FrameworkError> {
  return e instanceof RpcError && e.source === "framework";
}

export type FetchLike = (input: string, init?: RequestInit) => Promise<Response>;

export type ClientOptions = {
  baseUrl: string;
  fetch?: FetchLike;
  headers?: HeadersInit | (() => HeadersInit | Promise<HeadersInit>);
  credentials?: RequestCredentials;
  signal?: AbortSignal;
  /**
   * Observer for cross-cutting error handling (redirect-to-login, logging, telemetry).
   * Fires once per failed call with the thrown RpcError and the operation that produced
   * it, BEFORE the error rejects the call's promise. Side-effect only — the original error
   * ALWAYS still rejects, so per-call `.isError`/`isDomainError` handling keeps working.
   * Fires for every failure regardless of source (filter inside via `e.source` / the
   * `isMiddlewareError`/`isDomainError`/… guards); the only thing it does NOT fire for is an
   * aborted call (`code === "aborted"`) — any abort, per-call or client-level signal, is a
   * cancellation, not a failure. By convention, leave `domain` errors to the call site.
   * Keep it side-effect-only. It is invoked synchronously and not awaited: a
   * synchronous throw is logged and discarded (the original RpcError still rejects the
   * call), but an `async` hook's rejection escapes as an unhandled rejection — handle
   * your own errors if you do async work. NOTE: `op.input` is the raw request payload
   * (may contain credentials/PII); redact before logging. `op` reflects the call-site
   * `procedure`/`input`, not any values an interceptor reassigned on the request.
   */
  onError?: (error: RpcError, op: { procedure: string; input: unknown }) => void;
  /**
   * Ordered chain wrapping every call, between header resolution and the
   * transport. Unlike `onError` (a fire-and-forget observer), an interceptor is
   * awaited and controls the call: it can mutate the request, inspect the
   * result, and — by catching a rejection, awaiting work, and calling `next`
   * again — refresh a token and replay the call in-band. The first interceptor
   * is outermost. `onError` fires only after the chain is exhausted, so a call an
   * interceptor recovers never reaches it. See the README "Interceptors" section.
   */
  interceptors?: readonly RpcInterceptor[];
};

export type Client = {
  call<I, O>(
    procedure: string,
    input: I,
    init?: {
      signal?: AbortSignal;
      headers?: HeadersInit;
    },
  ): Promise<O>;
};

export type CallInit = { signal?: AbortSignal; headers?: HeadersInit };

/**
 * A generated procedure: callable like `client.users.get(input)`, with an
 * `isError` guard that narrows a caught value to this procedure's declared
 * error union `E` — `if (client.users.get.isError(e)) { e.code ... }`. The
 * guard is sound: it matches `e.code` against the procedure's declared codes at
 * runtime, so transport-level errors (`network_error`/`transport_error`/
 * `aborted`) are excluded — use {@link isRpcError} to handle those.
 */
export type RpcMethod<I, O, E extends RpcError = RpcError> = {
  (input: I, init?: CallInit): Promise<O>;
  isError(e: unknown): e is E;
};

/**
 * Builds a typed {@link RpcMethod} bound to a client, procedure name, and the
 * procedure's declared error `codes`. `.isError` narrows to `E` by checking
 * `e.code` against `codes` at runtime, so it never mistakes a client-synthesized
 * `network_error`/`transport_error`/`aborted` for a domain error.
 */
export function rpcMethod<I, O, E extends RpcError = RpcError>(
  client: Client,
  procedure: string,
  codes: readonly string[] = [],
): RpcMethod<I, O, E> {
  const isError = (e: unknown): e is E => e instanceof RpcError && codes.includes(e.code);
  return Object.assign((input: I, init?: CallInit) => client.call<I, O>(procedure, input, init), {
    isError,
  });
}

/** An {@link RpcMethod} with its type parameters erased — the runtime shape all methods share. */
export type AnyRpcMethod = RpcMethod<unknown, unknown, RpcError>;

/**
 * Brand check for a generated procedure. Lives here because this package owns
 * `RpcMethod`/{@link rpcMethod}, so framework adapters share one authoritative
 * predicate instead of each re-deriving the shape (and drifting from it).
 */
export function isRpcMethod(value: unknown): value is AnyRpcMethod {
  return typeof value === "function" && "isError" in value && typeof value.isError === "function";
}

/**
 * The query key for a procedure: `[...path, input]`, or the bare `[...path]`
 * prefix when `input` is omitted (matches every key under the procedure, e.g.
 * for cache invalidation). Framework-agnostic: TanStack, Vue, and Svelte Query
 * all key on `readonly unknown[]`.
 */
export function deriveKey(path: readonly string[], input?: unknown): readonly unknown[] {
  return input === undefined ? [...path] : [...path, input];
}

/**
 * Walks a generated client tree and replaces each {@link RpcMethod} leaf with
 * `makeLeaf(method, path)`, preserving the namespace shape. This is the
 * framework-free half of an adapter: a `@elixir-ts-rpc/react` (or Vue/Svelte)
 * package supplies `makeLeaf` to bind the method to its own query primitives.
 */
export function buildProxy<Leaf>(
  client: object,
  makeLeaf: (method: AnyRpcMethod, path: readonly string[]) => Leaf,
): unknown {
  const walk = (
    node: Record<string, unknown>,
    path: readonly string[],
  ): Record<string, unknown> => {
    const out: Record<string, unknown> = {};
    for (const key of Object.keys(node)) {
      const value = node[key];
      const childPath = [...path, key];
      if (isRpcMethod(value)) out[key] = makeLeaf(value, childPath);
      else if (value !== null && typeof value === "object")
        out[key] = walk(value as Record<string, unknown>, childPath);
      else out[key] = value;
    }
    return out;
  };
  return walk(client as Record<string, unknown>, []);
}

export function createClient(opts: ClientOptions): Client {
  const fetchFn = opts.fetch ?? globalThis.fetch.bind(globalThis);
  const credentials = opts.credentials ?? "same-origin";
  const base = opts.baseUrl.replace(/\/$/, "");
  if (base.includes("?")) {
    throw new Error(
      `@elixir-ts-rpc/client: baseUrl must not contain a query string. Got: ${opts.baseUrl}`,
    );
  }

  const invoke = chainInterceptors(opts.interceptors ?? [], async (req: RpcRequest) => {
    const path = encodeURIComponent(req.procedure.replace(/^\//, ""));
    const output = await doFetch(
      fetchFn,
      `${base}/${path}`,
      req.input,
      req.headers,
      credentials,
      req.signal,
    );
    return { output };
  });

  return {
    async call<I, O>(
      procedure: string,
      input: I,
      init?: {
        signal?: AbortSignal;
        headers?: HeadersInit;
      },
    ): Promise<O> {
      const baseHeaders =
        typeof opts.headers === "function" ? await opts.headers() : (opts.headers ?? {});

      const headers = new Headers(baseHeaders);
      headers.set("Content-Type", "application/json");
      if (init?.headers) {
        new Headers(init.headers).forEach((value, key) => {
          headers.set(key, value);
        });
      }

      const signal = combineSignals(opts.signal, init?.signal);

      try {
        const { output } = await invoke({ procedure, input, headers, signal });
        return output as O;
      } catch (error) {
        if (error instanceof RpcError && error.code !== "aborted") {
          try {
            opts.onError?.(error, { procedure, input });
          } catch (hookError) {
            console.error(
              "@elixir-ts-rpc/client: onError hook threw, original error still rejects",
              hookError,
            );
          }
        }
        throw error;
      }
    },
  };
}
