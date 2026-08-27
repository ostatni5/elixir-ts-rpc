# React + TanStack Query

`@elixir-ts-rpc/react` wraps your generated client in
[TanStack Query](https://tanstack.com/query) hooks. Every procedure gets its own
`useQuery` and `useMutation` hooks. It also gets `queryOptions` and
`mutationOptions` factories. Input, output, and error types are kept. So `data`
and `error` are never `unknown`.

The package builds on [the client](/guide/client). The transport, typed errors,
and abort behavior are the same. You still generate `rpc.gen.ts` with
`mix rpc.gen.ts`.

## Install

```sh
npm install @elixir-ts-rpc/react @elixir-ts-rpc/client @tanstack/react-query
```

Peer dependencies you provide: `@tanstack/react-query` (v5+),
`@elixir-ts-rpc/client`, `react` (v18+).

## Set up the adapter

Build the adapter once from your generated client. It has the same shape as the
client: `client.users.list` becomes `rpc.users.list`. Mount your own
`<QueryClientProvider>`. The adapter does not create one.

```ts twoslash
// rpc.ts
import { createRpcReact } from "@elixir-ts-rpc/react";
import { createRpcClient } from "./rpc.gen";

export const rpc = createRpcReact(createRpcClient({ baseUrl: "/rpc" }));
```

## Queries

The first argument is the input. You can leave it out when the procedure needs
none. The second argument takes any `useQuery` option. The only exceptions are
`queryKey` and `queryFn`. The adapter sets those.

```tsx twoslash
import { rpc } from "./rpc";

function Users() {
  const users = rpc.users.list.useQuery();

  if (users.isPending) return <p>Loading…</p>;
  if (users.isError) return <p>Failed: {users.error.message}</p>;

  return (
    <ul>
      {users.data.users.map((u) => (
        <li key={u.id}>{u.email}</li>
      ))}
    </ul>
  );
}
```

Query cancellation is automatic. The adapter passes TanStack's `signal` into the
call. So a query that unmounts or gets replaced aborts its request.

Always call hooks. Never wrap them in an `if`. To turn a query off, use
`enabled`. You can also pass `skipToken` as the input. `skipToken` keeps the
types safe.

```tsx twoslash
import { rpc } from "./rpc";
declare const id: string | undefined;
// ---cut---
import { skipToken } from "@tanstack/react-query";

// skipToken narrows the input: a missing id is a type error,
// not a runtime `undefined`.
const user = rpc.users.get.useQuery(id ? { id } : skipToken);
```

A skipped query keys under `[...path, {}]`, not under your input. So a switch
from `skipToken` to a real input changes the key.

## Mutations

`mutate` takes the procedure's input as its variables. Mutations get no abort
signal. The adapter passes no init to `mutationFn`. The automatic cancellation
above covers queries only.

```tsx twoslash
import { rpc } from "./rpc";
// ---cut---
import { useQueryClient } from "@tanstack/react-query";

function EditEmail({ id }: { id: string }) {
  const queryClient = useQueryClient();
  const update = rpc.users.update.useMutation({
    onSuccess: () =>
      queryClient.invalidateQueries({ queryKey: rpc.users.list.queryKey() }),
  });

  return (
    <button type="button" onClick={() => update.mutate({ id, email: "new@example.com" })}>
      {update.isPending ? "Saving…" : "Save"}
    </button>
  );
}
```

## Query keys and invalidation

`queryKey` builds `[...procedurePath, input]`. With no argument it builds only
`[...procedurePath]`. That shorter key is a prefix. Keys are hierarchical, so you
can invalidate at any level:

```ts twoslash
import { QueryClient } from "@tanstack/react-query";
import { rpc } from "./rpc";
import type { UsersListInput } from "./rpc.gen";
const queryClient = new QueryClient();
declare const filter: UsersListInput["filter"];
// ---cut---
queryClient.invalidateQueries({ queryKey: rpc.users.list.queryKey({ filter }) }); // one input
queryClient.invalidateQueries({ queryKey: rpc.users.list.queryKey() });           // every list query
queryClient.invalidateQueries({ queryKey: ["users"] });                           // all users.* queries
```

::: warning `queryKey()` is a prefix, not an exact key
A live query's key always holds its input. A missing input runs as `{}`. For
`getQueryData` and `setQueryData`, pass the input the query used:
`rpc.users.list.queryKey({ filter })`. For a query with no argument, use
`queryKey({})`.
:::

`queryFilter` wraps that key in a `QueryFilters` object. Use it with the cache
APIs that change the cache. It merges any filter fields you pass:

```ts twoslash
import { QueryClient } from "@tanstack/react-query";
import { rpc } from "./rpc";
import type { UsersListInput } from "./rpc.gen";
const queryClient = new QueryClient();
declare const filter: UsersListInput["filter"];
// ---cut---
queryClient.invalidateQueries(rpc.users.list.queryFilter());              // every list query
queryClient.cancelQueries(rpc.users.list.queryFilter({ filter }, { exact: true }));
```

### Scoping keys with a prefix

`queryKeyPrefix` puts every key under a scope. It defaults to `[]`. Use it for
per-tenant caches, or when two adapters share one `QueryClient`:

```ts twoslash
import { createRpcReact } from "@elixir-ts-rpc/react";
import { createRpcClient } from "./rpc.gen";
declare const tenantId: string;
// ---cut---
export const rpc = createRpcReact(createRpcClient({ baseUrl: "/rpc" }), {
  queryKeyPrefix: ["tenant", tenantId],
});
```

Keys become `[...prefix, ...procedurePath, input]`. The `queryKey` builder adds
the prefix too. So invalidation with `rpc.*.queryKey()` keeps working. Mutation
keys are not affected. Keep the prefix serializable and stable. Build a new
adapter when the scope changes.
Hand-written keys like `["users"]` no longer match. Use
`rpc.users.list.queryKey()` instead.

## Option factories

`queryOptions` and `mutationOptions` return plain typed options. They work with
the TanStack Query APIs that take options, such as prefetch and `useQueries`.
The bound hooks only call these factories. Combine the factories yourself instead
of waiting for a bound hook.

Both `queryOptions` and `useQuery` take a `TData` generic. It defaults to the
output type. Pass `select` to re-type `data`.

```ts twoslash
import { QueryClient } from "@tanstack/react-query";
import { rpc } from "./rpc";
import type { UsersListInput } from "./rpc.gen";
const queryClient = new QueryClient();
declare const filter: UsersListInput["filter"];
// ---cut---
import { useQueries } from "@tanstack/react-query";

await queryClient.prefetchQuery(rpc.users.list.queryOptions({ filter }));

// Run several procedures in parallel; each result stays typed.
const [me, list] = useQueries({
  queries: [rpc.auth.me.queryOptions(), rpc.users.list.queryOptions({ filter })],
});
```

## Suspense

Suspense has its own factory and its own bound hook. Under suspense `data` is
always defined, so there is no pending branch to write.

```tsx twoslash
import { rpc } from "./rpc";
import type { UsersListInput } from "./rpc.gen";
declare const filter: UsersListInput["filter"];
// ---cut---
import { useSuspenseQuery } from "@tanstack/react-query";

// Bound hook.
const users = rpc.users.list.useSuspenseQuery({ filter });

// Or the factory, for TanStack's own suspense APIs.
const same = useSuspenseQuery(rpc.users.list.suspenseQueryOptions({ filter }));

users.data.users.map((u) => u.email);
```

Use `suspenseQueryOptions`, not `queryOptions`. TanStack's suspense options
reject a `queryFn` that admits `skipToken`, and `queryOptions` allows one. So
passing `queryOptions` to `useSuspenseQuery` is a type error.

A suspense query cannot be disabled. `skipToken` is rejected here, and the input
stays required. Both factories share one key space, so a suspense query and a
normal query for the same input share a cache entry.

## Infinite queries

`infiniteQueryOptions` builds options for TanStack's `useInfiniteQuery`. The
bound `useInfiniteQuery` calls it for you. Both require an input argument, and
neither accepts `skipToken`. The adapter cannot guess your cursor field. (tRPC
assumes it is named `cursor`.) So tell it how to merge the page param into the
input with `pageInput`:

```tsx twoslash
import { rpc } from "./rpc";
import type { EpochMillis } from "./rpc.gen";
// ---cut---
const pages = rpc.users.list.useInfiniteQuery(
  {},
  {
    initialPageParam: undefined as EpochMillis | undefined,
    getNextPageParam: (last) => last.meta.range.since ?? undefined,
    pageInput: (input, since) => ({ ...input, filter: { ...input.filter, since } }),
  },
);
// pages.data.pages.flatMap((p) => p.users)
```

`EpochMillis` is a generated branded type. The page param uses it, not `number`.
`pageInput` returns the procedure's own input type. So the cursor field must
already exist in the `@spec`. An unknown field is rejected.

`infiniteQueryKey()` works like `queryKey()`. Infinite keys carry a `$infinite`
marker before the input. So an exact single-page key never matches an infinite
one. The shorter prefix still matches both. So `queryKey()` or `queryFilter()`
with no input also invalidates the infinite queries. One procedure can serve both
a `useQuery` and a `useInfiniteQuery`. `queryKeyPrefix` applies to infinite keys
too.

## Errors

`error` holds the declared error union plus transport errors. It is never
`unknown`. Narrow it with:

| Tool                                  | What it does                                                  |
| ------------------------------------- | ------------------------------------------------------------- |
| `rpc.users.update.isError(err)`       | matches the declared codes, transport errors go to a fallback |
| `isTransportError`, `isDomainError`   | narrow by source (from `@elixir-ts-rpc/client`)               |
| `RpcErrorOf<typeof rpc.users.update>` | names the declared union for a helper signature               |
| `RpcInputOf`, `RpcOutputOf`           | the same as tRPC `inferInput` and `inferOutput`               |

A framework error such as `input_validation_failed` can carry a `code` outside
that union. So always keep a `default` or `else` branch. For shared handling like
redirect-to-login, use the client's `onError`. The full guard model is in
[Using the client](/guide/client).

## Other frameworks

This package is only for TanStack Query. The generated client itself is
framework-free. `client.users.list(input, { signal })` returns a typed promise.
It has typed errors and abort support. Use it with SWR, Vue, Svelte, or plain
`fetch`. The framework-free core is documented in
[Using the client](/guide/client).

## Not built yet

- **Subscriptions.** There is no realtime hook. The library has no realtime
  transport yet (see [getting started](/guide/getting-started#not-built-yet)).
- **SSR hydration.** Use the option factories with TanStack's own hydration APIs.
