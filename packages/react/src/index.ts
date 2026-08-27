import {
  type AnyRpcMethod,
  buildProxy,
  deriveKey,
  type RpcError,
  type RpcMethod,
  type TransportError,
} from "@elixir-ts-rpc/client";
import {
  type InfiniteData,
  type QueryFilters,
  type QueryFunction,
  type QueryKey,
  type SkipToken,
  skipToken,
  type UseInfiniteQueryOptions,
  type UseInfiniteQueryResult,
  type UseMutationOptions,
  type UseMutationResult,
  type UseQueryOptions,
  type UseQueryResult,
  type UseSuspenseQueryOptions,
  type UseSuspenseQueryResult,
  useInfiniteQuery,
  useMutation,
  useQuery,
  useSuspenseQuery,
} from "@tanstack/react-query";

// A failed call surfaces either the procedure's declared error `E` or a
// client-synthesized transport error (network/abort), so the hook error type
// must admit both — otherwise `error.code` narrowing lies about network failures.
type HookError<E extends RpcError> = E | TransportError;

// The input argument is optional only when the procedure's input has no required
// fields, so `rpc.auth.me.useQuery()` works but `rpc.users.get.useQuery({ id })`
// still requires its input. `skipToken` is always accepted in the input position
// to disable the query type-safely (TanStack's alternative to `enabled: false`).
type QueryArgs<I, O, E extends RpcError, TData> =
  Record<string, never> extends I
    ? [input?: I | SkipToken, options?: RpcQueryOptions<O, E, TData>]
    : [input: I | SkipToken, options?: RpcQueryOptions<O, E, TData>];

export type RpcQueryOptions<O, E extends RpcError, TData = O> = Omit<
  UseQueryOptions<O, HookError<E>, TData, QueryKey>,
  "queryKey" | "queryFn"
>;

// A suspense query cannot be disabled, so `skipToken` is not accepted here and
// the input stays required when the procedure has required fields. TanStack's
// `UseSuspenseQueryOptions` also excludes `SkipToken` from `queryFn`, which is
// why the plain `queryOptions` result is not assignable to a suspense hook.
type SuspenseQueryArgs<I, O, E extends RpcError, TData> =
  Record<string, never> extends I
    ? [input?: I, options?: RpcSuspenseQueryOptions<O, E, TData>]
    : [input: I, options?: RpcSuspenseQueryOptions<O, E, TData>];

export type RpcSuspenseQueryOptions<O, E extends RpcError, TData = O> = Omit<
  UseSuspenseQueryOptions<O, HookError<E>, TData, QueryKey>,
  "queryKey" | "queryFn"
>;

export type RpcMutationOptions<O, E extends RpcError, I> = Omit<
  UseMutationOptions<O, HookError<E>, I>,
  "mutationFn"
>;

/** A `queryFilter` argument: any `QueryFilters` field except `queryKey`, which the adapter derives. */
export type RpcQueryFilters = Omit<QueryFilters, "queryKey">;

export type RpcInfiniteQueryOptions<
  I,
  O,
  E extends RpcError,
  TPageParam,
  TData = InfiniteData<O>,
> = Omit<
  UseInfiniteQueryOptions<O, HookError<E>, TData, QueryKey, TPageParam>,
  "queryKey" | "queryFn"
> & {
  /**
   * Folds each page's `pageParam` into the procedure input for that page's call.
   * The adapter can't assume a cursor field name (unlike tRPC's implicit
   * `cursor`), so you name it: `(input, cursor) => ({ ...input, since: cursor })`.
   */
  pageInput: (input: I, pageParam: TPageParam) => I;
};

/**
 * The TanStack Query surface attached to one generated procedure. The
 * procedure's input/output and its error union flow into every member, so
 * `data` is typed and `error` is `E | TransportError`.
 */
export interface RpcQueryLeaf<I, O, E extends RpcError> {
  /**
   * `[...procedurePath, input]`, or the bare `[...procedurePath]` prefix when
   * called with no argument — the prefix matches every query under the procedure
   * for `invalidateQueries`, but is NOT the exact key of a live query. A live
   * query always stores under its input, and an omitted input runs as `{}`, so
   * for `getQueryData`/`setQueryData` pass the input the query used —
   * `queryKey({})` for a no-argument query, not `queryKey()`.
   */
  queryKey(input?: I): QueryKey;
  /**
   * A `QueryFilters` targeting this procedure — pass to `invalidateQueries`,
   * `cancelQueries`, etc. Omitting `input` matches every query under the
   * procedure (the hierarchical prefix); passing it narrows to that one input.
   */
  queryFilter(input?: I, filters?: RpcQueryFilters): QueryFilters;
  queryOptions<TData = O>(
    ...args: QueryArgs<I, O, E, TData>
  ): UseQueryOptions<O, HookError<E>, TData, QueryKey>;
  /**
   * Like {@link queryOptions}, but typed for TanStack's suspense hooks. Use it
   * with `useSuspenseQuery`; the plain `queryOptions` result is not assignable
   * there, because its `queryFn` admits `skipToken`. Shares the single-page key
   * space, so a suspense query and a normal query for the same input share one
   * cache entry. A suspense query cannot be disabled, so `skipToken` is not
   * accepted.
   */
  suspenseQueryOptions<TData = O>(
    ...args: SuspenseQueryArgs<I, O, E, TData>
  ): UseSuspenseQueryOptions<O, HookError<E>, TData, QueryKey>;
  mutationOptions(options?: RpcMutationOptions<O, E, I>): UseMutationOptions<O, HookError<E>, I>;
  /** Like {@link queryKey}, but for this procedure's infinite queries — a key space distinct from single-page queries, so the two never collide in the cache. */
  infiniteQueryKey(input?: I): QueryKey;
  infiniteQueryOptions<TPageParam, TData = InfiniteData<O>>(
    input: I,
    options: RpcInfiniteQueryOptions<I, O, E, TPageParam, TData>,
  ): UseInfiniteQueryOptions<O, HookError<E>, TData, QueryKey, TPageParam>;
  useQuery<TData = O>(...args: QueryArgs<I, O, E, TData>): UseQueryResult<TData, HookError<E>>;
  /** Suspense variant of {@link useQuery}: `data` is always defined, and there is no pending state. */
  useSuspenseQuery<TData = O>(
    ...args: SuspenseQueryArgs<I, O, E, TData>
  ): UseSuspenseQueryResult<TData, HookError<E>>;
  useInfiniteQuery<TPageParam, TData = InfiniteData<O>>(
    input: I,
    options: RpcInfiniteQueryOptions<I, O, E, TPageParam, TData>,
  ): UseInfiniteQueryResult<TData, HookError<E>>;
  useMutation(options?: RpcMutationOptions<O, E, I>): UseMutationResult<O, HookError<E>, I>;
  /** Narrows a caught value to this procedure's declared errors `E` (transport codes are excluded — use `isTransportError`). */
  isError(e: unknown): e is E;
}

export type RpcReact<T> = {
  [K in keyof T]: NonNullable<T[K]> extends RpcMethod<infer I, infer O, infer E>
    ? RpcQueryLeaf<I, O, E>
    : RpcReact<NonNullable<T[K]>>;
};

/** The declared error union of a procedure, read off its adapter leaf. */
export type RpcErrorOf<L> = L extends RpcQueryLeaf<infer _I, infer _O, infer E> ? E : never;

/** The input type of a procedure, read off its adapter leaf (mirrors tRPC's `inferInput`). */
export type RpcInputOf<L> = L extends RpcQueryLeaf<infer I, infer _O, infer _E> ? I : never;

/** The output type of a procedure, read off its adapter leaf (mirrors tRPC's `inferOutput`). */
export type RpcOutputOf<L> = L extends RpcQueryLeaf<infer _I, infer O, infer _E> ? O : never;

export type RpcReactOptions = {
  /**
   * Prepended to every derived query key, so an adapter's cache lives under its
   * own scope (per-tenant, per-adapter-instance). The prefix flows into both the
   * `queryKey` builder and the `queryOptions`/`useQuery` keys, so hierarchical
   * invalidation via `rpc.*.queryKey()` keeps working unchanged. It becomes part
   * of every key, so it must be serializable and stable for the adapter's
   * lifetime — recreate the adapter if the scope changes. Mutations are unaffected.
   *
   * With a prefix set, hand-rolled invalidation like `queryKey: ["users"]` no
   * longer matches (keys are now `[...prefix, "users", …]`) — invalidate through
   * the leaf's `queryKey()` builder, which includes the prefix.
   */
  queryKeyPrefix?: readonly unknown[];
};

// Marks the infinite-query key space, keeping `useInfiniteQuery` and single-page
// `useQuery` for the same procedure+input in separate cache entries (their data
// shapes differ: `InfiniteData<O>` vs `O`). Sits before the input, so a
// single-page exact key is never a prefix of an infinite one.
const INFINITE = "$infinite";

function makeLeaf(method: AnyRpcMethod, path: readonly string[], prefix: readonly unknown[]) {
  const withPrefix = (k: readonly unknown[]): QueryKey =>
    prefix.length === 0 ? k : [...prefix, ...k];
  const key = (input?: unknown): QueryKey => withPrefix(deriveKey(path, input));
  const infiniteKey = (input?: unknown): QueryKey =>
    withPrefix(deriveKey([...path, INFINITE], input));

  const queryOptions = (input?: unknown, options?: object) => {
    if (input === skipToken) {
      const disabled: UseQueryOptions<unknown, unknown, unknown, QueryKey> = {
        ...options,
        queryKey: key({}),
        queryFn: skipToken,
      };
      return disabled;
    }
    const resolved = input ?? {};
    const queryFn: QueryFunction<unknown, QueryKey> = ({ signal }) => method(resolved, { signal });
    return { ...options, queryKey: key(resolved), queryFn };
  };

  // No skipToken branch: a suspense query cannot be disabled, so `queryFn` is
  // always a real function. That is exactly what UseSuspenseQueryOptions wants.
  const suspenseQueryOptions = (input?: unknown, options?: object) => {
    const resolved = input ?? {};
    const queryFn: QueryFunction<unknown, QueryKey> = ({ signal }) => method(resolved, { signal });
    return { ...options, queryKey: key(resolved), queryFn };
  };

  const infiniteQueryOptions = (
    input: unknown,
    options: Record<string, unknown> & {
      pageInput: (input: unknown, pageParam: unknown) => unknown;
    },
  ): UseInfiniteQueryOptions<unknown, unknown, unknown, QueryKey, unknown> => {
    const { pageInput, ...rest } = options;
    const queryFn: QueryFunction<unknown, QueryKey, unknown> = ({ pageParam, signal }) =>
      method(pageInput(input, pageParam), { signal });
    return { ...rest, queryKey: infiniteKey(input), queryFn } as UseInfiniteQueryOptions<
      unknown,
      unknown,
      unknown,
      QueryKey,
      unknown
    >;
  };

  const mutationOptions = (options?: object) => ({
    ...options,
    mutationFn: (input: unknown) => method(input),
  });

  return {
    queryKey: key,
    queryFilter: (input?: unknown, filters?: object) => ({ ...filters, queryKey: key(input) }),
    queryOptions,
    suspenseQueryOptions,
    infiniteQueryKey: infiniteKey,
    infiniteQueryOptions,
    mutationOptions,
    useQuery: (input?: unknown, options?: object) => useQuery(queryOptions(input, options)),
    useSuspenseQuery: (input?: unknown, options?: object) =>
      useSuspenseQuery(suspenseQueryOptions(input, options)),
    useInfiniteQuery: (
      input: unknown,
      options: Record<string, unknown> & {
        pageInput: (input: unknown, pageParam: unknown) => unknown;
      },
    ) => useInfiniteQuery(infiniteQueryOptions(input, options)),
    useMutation: (options?: object) => useMutation(mutationOptions(options)),
    isError: method.isError,
  };
}

/**
 * Wraps a generated RPC client (the object from `createRpcClient`) in a
 * same-shaped tree of TanStack Query helpers:
 *
 * ```ts
 * import { createRpcReact } from "@elixir-ts-rpc/react";
 * import { createRpcClient } from "./rpc.gen";
 *
 * export const rpc = createRpcReact(createRpcClient({ baseUrl: "/rpc" }));
 * ```
 *
 * Bring your own `<QueryClientProvider>`; this adapter does not create one. The
 * bound `useQuery`/`useMutation` are React hooks — call them unconditionally at
 * the top of a component and gate fetching with the `enabled` option.
 *
 * Pass `{ queryKeyPrefix }` to scope every key under a prefix — see
 * {@link RpcReactOptions}.
 */
export function createRpcReact<T extends object>(
  client: T,
  options?: RpcReactOptions,
): RpcReact<T> {
  const prefix = options?.queryKeyPrefix ?? [];
  return buildProxy(client, (method, path) => makeLeaf(method, path, prefix)) as RpcReact<T>;
}
