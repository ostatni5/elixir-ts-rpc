# Using the client

The TypeScript side is the [`@elixir-ts-rpc/client`](https://www.npmjs.com/package/@elixir-ts-rpc/client)
package plus the `rpc.gen.ts` file [codegen](/guide/codegen-workflow) emits from
your `@spec`s. This page walks the runtime client and its features.

::: tip Generated vs. runtime entry point
`@elixir-ts-rpc/client` ships the runtime. That is `createClient`, the `RpcError`
class, the error guards, and the interceptor types. It does **not** ship
per-procedure types. Codegen wraps `createClient` in a typed
**`createRpcClient`** factory and writes it into your `rpc.gen.ts` alongside every
input/output/error type. So you import `createRpcClient` from your own generated
file, and the guards/types from the package.
:::

## Creating a client

```ts
import { createRpcClient } from "./rpc.gen";

const client = createRpcClient({ baseUrl: "/rpc" });
```

`createRpcClient` and the underlying `createClient` accept:

| Option         | Type                        | Default            | Notes                                           |
| -------------- | --------------------------- | ------------------ | ----------------------------------------------- |
| `baseUrl`      | `string`                    | -                  | Where the RPC plug is mounted (no query string) |
| `headers`      | `HeadersInit` or a thunk    | `{}`               | Static, or resolved before each call            |
| `credentials`  | `RequestCredentials`        | `"same-origin"`    | `"include"` for cross-origin cookies            |
| `signal`       | `AbortSignal`               | -                  | Client-wide abort signal                        |
| `fetch`        | `FetchLike`                 | `globalThis.fetch` | Inject a custom fetch (SSR, tests)              |
| `onError`      | `(error, op) => void`       | -                  | Cross-cutting failure observer                  |
| `interceptors` | `readonly RpcInterceptor[]` | `[]`               | Ordered call-wrapping chain                     |

## Making calls

Generated methods are namespaced by procedure and fully typed. The input, output,
and error shapes all come from your `@spec`:

```ts
const user = await client.users.get({ id: 1 });
//    ^? { id: number; name: string }
```

Each method takes an optional second `init` argument for per-call overrides, a
`signal` and extra `headers`:

```ts
const user = await client.users.get({ id: 1 }, { signal: controller.signal });
```

## Catching typed errors

Failures are thrown as `RpcError`. Every `RpcError` carries a `code`, a `source`
of `"transport" | "framework" | "middleware" | "domain"`, a `message` that falls
back to the `code`, optional `details`, and the HTTP `status`. There are three
ways to narrow a caught value, from most to least specific.

**Per-procedure `.isError`: sound, narrows to the procedure's declared error union.**
Each generated method carries an `.isError` guard that checks `e.code` against
that procedure's declared codes at runtime and narrows to its generated error
alias. Because it matches the declared codes, it excludes the client-synthesized
transport codes. Handle those separately. The declared union also includes any
middleware arms the procedure can fail with, such as `unauthorized`, which you
typically leave to a central `onError` rather than the per-call `switch`.

```ts
import { isTransportError } from "@elixir-ts-rpc/client";

try {
  await client.users.update({ id, email });
} catch (e) {
  if (client.users.update.isError(e)) {
    // e is narrowed to the procedure's error union. `e.code` is the declared set.
    switch (e.code) {
      case "email_taken":
        console.error("email already in use:", e.details);
        break;
      case "not_found":
        console.error("user no longer exists");
        break;
    }
  } else if (isTransportError(e)) {
    // e.code is "network_error" | "transport_error" | "aborted"
    console.error(`transport failure (${e.code}):`, e.message);
  } else {
    throw e;
  }
}
```

**`isTransportError`: sound, narrows to the transport union.** It catches only the
codes the client synthesizes when a call never produced a server error envelope:
`aborted`, `network_error`, `transport_error`. You get a literal `code` union you
can `switch` exhaustively.

**`isRpcError`: broad, narrows to `RpcError`.** When you don't need to
distinguish domain from transport, this narrows to `RpcError` with `e.code` as a
plain `string`. Always include a `default` branch.

```ts
import { isRpcError } from "@elixir-ts-rpc/client";

try {
  await client.users.update({ id, email });
} catch (e) {
  if (isRpcError(e)) {
    console.error(`rpc failed (${e.code}):`, e.message);
  } else {
    throw e;
  }
}
```

For cross-cutting handling there are also **source guards**:
`isDomainError`, `isMiddlewareError`, and `isFrameworkError`. They narrow by
`e.source` rather than by a specific procedure's codes. They're most useful in
`onError` and interceptors, where you don't have a single procedure in hand.

::: warning `details` is best-effort
The generated detail type reflects what the handler's `@spec` *declares*, but at
runtime `details` may be `undefined`. Transport errors never carry it, and a
server error may omit it. Always guard access with `e.details?.field`. Note also
that everything in a typed error's `message`/`details` is sent to the client
verbatim. See [Supported types](/guide/supported-types) and the
[full type reference](https://github.com/ostatni5/elixir-ts-rpc/blob/main/apps/rpc_elixir/docs/supported-types.md)
for the handler-side caveats.
:::

## Aborting requests

Pass an `AbortSignal` per call, client-wide, or both. They compose, so either
firing cancels the call:

```ts
const controller = new AbortController();
setTimeout(() => controller.abort(), 5_000);

const result = await client.users.list({}, { signal: controller.signal });
```

An aborted call rejects with an `RpcError` whose `code` is `"aborted"`. By
design, aborts are treated as cancellations, not failures. They never reach the
`onError` observer.

## Headers and credentials

`headers` can be static, or a thunk resolved before each call. Use the thunk to
attach a token that may change between calls. For cross-origin requests that
need cookies, set `credentials: "include"`:

```ts
const client = createRpcClient({
  baseUrl: "https://api.example.com/rpc",
  credentials: "include", // default is "same-origin"
  headers: async () => ({
    Authorization: `Bearer ${await getToken()}`,
  }),
});
```

## Central error handling

Pass an `onError` observer to handle failures cross-cuttingly, such as hard
redirects, logging, and telemetry. It fires once per failed call with the
`RpcError` and the operation that produced it, and you filter by source. It is
**side-effect only**. The original error always still rejects, so per-call
`.isError` handling keeps working.

```ts
import { isDomainError, isMiddlewareError } from "@elixir-ts-rpc/client";

const client = createRpcClient({
  baseUrl: "/rpc",
  onError: (e, { procedure }) => {
    if (isDomainError(e)) return; // leave to the call site
    if (isMiddlewareError(e) && e.code === "unauthorized") window.location.href = loginUrl;
    else console.warn(`RPC ${procedure} failed:`, e.source, e.code);
  },
});
```

::: warning A few sharp edges
Aborts never reach `onError`. Domain errors do, so filter them out unless you want
global logging. The hook is invoked synchronously and not awaited. A synchronous
throw is logged and discarded, but an `async` hook's rejection escapes as an
unhandled rejection, so handle your own errors if you do async work. And `op.input`
is the raw request payload, which may contain credentials or PII, so redact before
logging.
:::

## Interceptors

Where `onError` only observes, an **interceptor** controls the call. Each one
wraps the request between header resolution and the transport, receiving the
request and `next`, the rest of the chain. It is awaited, so it can mutate the
request and inspect the result. It can also catch a failure, `await` async work,
and call `next` again to **replay** the call. The first interceptor in the
array is outermost.

```ts
import type { RpcInterceptor } from "@elixir-ts-rpc/client";

const logging: RpcInterceptor = async (req, next) => {
  const started = performance.now();
  const res = await next(req);
  console.debug(`RPC ${req.procedure} ok in ${performance.now() - started}ms`);
  return res;
};

const client = createRpcClient({ baseUrl: "/rpc", interceptors: [logging] });
```

`onError` fires only after the chain is exhausted, so a call an interceptor
recovers by replaying successfully never reaches it.

### Auth refresh, with single-flight

The `headers` thunk is proactive and attaches a token before each call. For a
token that expires mid-flight, an interceptor catches the `401`, refreshes once
across all in-flight calls, and replays each with the new token. Set the
`Authorization` header **inside the interceptor** rather than the `headers` thunk,
so the replay picks up the fresh token rather than the stale one baked into the
original request.

```ts
import { isMiddlewareError, type RpcInterceptor } from "@elixir-ts-rpc/client";

let refreshing: Promise<void> | null = null; // single-flight: one refresh, many waiters

const authRefresh: RpcInterceptor = async (req, next) => {
  req.headers.set("Authorization", `Bearer ${getToken()}`);
  try {
    return await next(req);
  } catch (e) {
    if (!(isMiddlewareError(e) && e.code === "unauthorized")) throw e;
    refreshing ??= refreshToken().finally(() => (refreshing = null));
    await refreshing;
    req.headers.set("Authorization", `Bearer ${getToken()}`);
    return await next(req); // replay with the fresh token
  }
};

const client = createRpcClient({ baseUrl: "/rpc", interceptors: [authRefresh] });
```

Guard against a refresh loop in your own code. Cap to one replay, or have
`refreshToken` reject when the refresh token itself is dead. The interceptor
rethrows a second `401` to `onError` and the call site rather than retry forever.
For **cookie/session** auth there's no client-held token to refresh. Let the
server manage session lifetime and, on a `401`, send the user to log in rather
than attempting an in-band refresh. The [Phoenix example](/guide/examples) shows
a logging interceptor and source-filtered `onError` on a session-auth app.

## Raw untyped client

If you need to call procedures without generated types, `createClient` returns a
low-level `client.call(procedure, input, init?)` method:

```ts
import { createClient } from "@elixir-ts-rpc/client";

const client = createClient({ baseUrl: "/rpc" });
const me = await client.call("auth.me", {});
```

::: tip Canonical reference
This page mirrors the package README, which is the always-current source of
truth: [`@elixir-ts-rpc/client` README →](https://github.com/ostatni5/elixir-ts-rpc/blob/main/packages/client/README.md)
:::
