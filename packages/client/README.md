# @elixir-ts-rpc/client

Runtime client for [elixir-ts-rpc](https://github.com/ostatni5/elixir-ts-rpc),
typed RPC between Elixir and TypeScript. This is pre-1.0 (`0.0.2`), so the API
may change.

```sh
npm install @elixir-ts-rpc/client
```

## What's in here

This package ships the **runtime only**. It exports `createClient`, the
`RpcError` class, the narrowing guards (`isRpcError`, `isTransportError`,
`isDomainError`, `isMiddlewareError`, `isFrameworkError`),
`TRANSPORT_ERROR_CODES`, the `rpcMethod` helper, and the interceptor types.

The types for each procedure come from codegen. `mix rpc.gen.ts` writes a file
named `rpc.gen.ts`. That file wraps `createClient` in a typed factory called
**`createRpcClient`**. This package does not export `createRpcClient`. You
import it from your own generated file:

```ts
import { createRpcClient } from "./rpc.gen";

const client = createRpcClient({ baseUrl: "/rpc" });

// Types come from @spec. The second `init` arg sets signal and headers.
const user = await client.users.get({ id }, { signal: controller.signal });
```

Errors are thrown as `RpcError`. Every generated method has an `.isError`
guard. It matches the error union that the procedure declares:

```ts
try {
  await client.users.update({ id, email });
} catch (e) {
  if (client.users.update.isError(e)) {
    // e.code is the procedure's declared error union
  } else throw e;
}
```

No generated types yet? Use the low-level `client.call(procedure, input, init?)`.

## Documentation

**[Using the client →](https://ostatni5.github.io/elixir-ts-rpc/guide/client)**:
options, error narrowing, aborting, headers, credentials, `onError`,
interceptors, single-flight auth refresh.

Server side: [`elixir_ts_rpc` on HexDocs](https://hexdocs.pm/elixir_ts_rpc).
React hooks: [`@elixir-ts-rpc/react`](../react/README.md).

Want to see what codegen emits before writing any Elixir? The
[playground](https://elixir-ts-rpc-playground.netlify.app) runs the real
generator in your browser.
