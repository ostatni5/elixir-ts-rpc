# @elixir-ts-rpc/react

Typed React hooks for your generated
[elixir-ts-rpc](https://github.com/ostatni5/elixir-ts-rpc) client. They are
built on [TanStack Query](https://tanstack.com/query). Inputs, outputs, and
error unions flow into `useQuery` and `useMutation`. This is pre-1.0
(`0.0.2`), so the API may change.

```sh
npm install @elixir-ts-rpc/react @elixir-ts-rpc/client @tanstack/react-query
```

You provide the peer dependencies: `@tanstack/react-query` (v5+),
`@elixir-ts-rpc/client`, and `react` (v18+).

## Setup

You add your own `<QueryClientProvider>`. This package does not create one.

```ts
// rpc.ts
import { createRpcReact } from "@elixir-ts-rpc/react";
import { createRpcClient } from "./rpc.gen";

export const rpc = createRpcReact(createRpcClient({ baseUrl: "/rpc" }));
```

The adapter has the same shape as the client:

```tsx
const users = rpc.users.list.useQuery({ filter: {} });
// users.data is the typed output · users.error covers declared and transport errors

const update = rpc.users.update.useMutation();
update.mutate({ id: "u_1", email: "new@example.com" });
```

Every procedure also gives you `queryKey`, `queryFilter`, `queryOptions`,
`mutationOptions`, `infiniteQueryOptions`, and an `isError` guard.

## Documentation

**[React + TanStack Query →](https://ostatni5.github.io/elixir-ts-rpc/guide/react)**:
query keys, invalidation, key prefixes, option factories, infinite queries,
typed errors, adapters for other frameworks.

Client: [`@elixir-ts-rpc/client`](../client/README.md).
Server: [`elixir_ts_rpc` on HexDocs](https://hexdocs.pm/elixir_ts_rpc).

Want to see what codegen emits before writing any Elixir? The
[playground](https://elixir-ts-rpc-playground.netlify.app) runs the real
generator in your browser.
