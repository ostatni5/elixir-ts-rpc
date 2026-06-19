# @elixir-ts-rpc/client

Runtime client for [elixir-ts-rpc](https://github.com/ostatni5/elixir-ts-rpc), a typed RPC bridge between Elixir and TypeScript.

> **Status:** early release (`0.0.1`), pre-1.0. The API may change before 1.0.
> For an end-to-end setup, see
> [examples/basic](https://github.com/ostatni5/elixir-ts-rpc/tree/main/examples/basic).

## Installation

```sh
npm install @elixir-ts-rpc/client
```

## Usage

The package's main runtime entry point is **`createClient`**. It also exports the
`RpcError` class, the error-narrowing guards (`isRpcError`, `isTransportError`,
`isDomainError`, `isMiddlewareError`, `isFrameworkError`), the
`TRANSPORT_ERROR_CODES` constant, the `rpcMethod` helper, and interceptor types.
It does *not* ship per-procedure types. Those are emitted by codegen.

Running `mix rpc.gen.ts` reads your Elixir router's `@spec` annotations and
generates an `rpc.gen.ts` file that wraps `createClient` in a typed
**`createRpcClient`** factory, alongside all input/output/error types.
`createRpcClient` is therefore a *generated* symbol you import from your own
`rpc.gen.ts`, not from this package.

### Typed client (generated)

After running `mix rpc.gen.ts --router YourApp.Router --out src/rpc.gen.ts`,
import the generated factory:

```ts
import { createRpcClient } from "./rpc.gen";

const client = createRpcClient({ baseUrl: "/rpc" });

// Fully typed: input, output, and error shapes come from @spec
const user = await client.users.get({ id });
```

Each generated method also accepts an optional `init` argument for per-call
overrides:

```ts
const user = await client.users.get({ id }, { signal: controller.signal });
```

### Catching typed errors

Errors are thrown as `RpcError`. There are three ways to narrow a caught value,
from most to least specific:

**Per-procedure `.isError` (sound, narrows to the domain union).** Each
generated method carries an `.isError` guard that checks `e.code` against that
procedure's declared codes at runtime and narrows to its error alias (e.g.
`UsersUpdateError`). Because it matches the declared codes, it excludes the
client-synthesized transport codes, so handle those separately.

```ts
import { isTransportError } from "@elixir-ts-rpc/client";

try {
  await client.users.update({ id, email });
} catch (e) {
  if (client.users.update.isError(e)) {
    // e is narrowed to UsersUpdateError, `e.code` is the declared union.
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

> **`RpcError.details` is best-effort.** The generated detail type reflects what
> the handler's `@spec` *declares*, but at runtime `details` may be `undefined`.
> Framework-level errors (e.g. transport failures) carry no domain details, and
> the field is typed optional. Always guard access (`e.details?.field`). Note also
> that on the server everything in a typed error's `message`/`details` is sent to
> the client verbatim, see
> [Typed-error message and details are sent verbatim](https://github.com/ostatni5/elixir-ts-rpc/blob/main/apps/rpc_elixir/docs/supported-types.md#error-details)
> for the handler-side caveats.

**`isTransportError` (sound, narrows to the transport union).** Catches only the
codes the client synthesizes when a request never reached a handler
(`network_error`, `transport_error`, `aborted`), giving a literal `code` union
you can `switch` exhaustively.

**`isRpcError` (broad, narrows to `RpcError`).** When you don't need to
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

### Abort signal

```ts
const controller = new AbortController();
setTimeout(() => controller.abort(), 5_000);

const result = await client.users.list({}, { signal: controller.signal });
```

### Cross-origin with a bearer token

```ts
const client = createRpcClient({
  baseUrl: "https://api.example.com/rpc",
  credentials: "include", // default is "same-origin"
  headers: async () => ({
    Authorization: `Bearer ${await getToken()}`,
  }),
});
```

### Central error handling

Pass an `onError` observer to handle failures cross-cuttingly: hard redirects,
logging, telemetry. It fires once per failed call with the `RpcError` and the
operation that produced it, and you filter by source. It is side-effect only: the
original error **always** still rejects, so per-call `.isError` handling keeps
working.

```ts
import { isDomainError, isMiddlewareError } from "@elixir-ts-rpc/client";

const rpc = createRpcClient({
  baseUrl: "/rpc",
  onError: (e, { procedure }) => {
    if (isDomainError(e)) return; // leave to the call site
    if (isMiddlewareError(e) && e.code === "unauthorized") window.location.href = loginUrl;
    else console.warn(`RPC ${procedure} failed:`, e.source, e.code);
  },
});
```

Aborts never reach it. Domain errors do (filter them out unless you want global
logging). The hook is invoked synchronously and not awaited: if it throws, that
failure is logged and discarded, but an `async` hook's rejection escapes as an
unhandled rejection, so handle your own errors if you do async work. Note that
`op.input` is the raw request payload (may contain credentials/PII). Redact before
logging.

### Interceptors

Where `onError` only observes, an **interceptor** controls the call. Each one
wraps the request between header resolution and the transport, receiving the
request and `next` (the rest of the chain). It is awaited, so it can mutate the
request, inspect the result, and, crucially, catch a failure, `await` async
work, and call `next` again to **replay** the call. The first interceptor in the
array is outermost.

```ts
import type { RpcInterceptor } from "@elixir-ts-rpc/client";

const logging: RpcInterceptor = async (req, next) => {
  const started = performance.now();
  const res = await next(req);
  console.debug(`RPC ${req.procedure} ok in ${performance.now() - started}ms`);
  return res;
};

const rpc = createRpcClient({ baseUrl: "/rpc", interceptors: [logging] });
```

`onError` fires only after the chain is exhausted, so a call an interceptor
recovers (by replaying successfully) never reaches it.

### Auth refresh (reactive, with single-flight)

The `headers` thunk is proactive (attach a token before each call). For a token
that expires mid-flight, an interceptor catches the `401`, refreshes once across
all in-flight calls, and replays each with the new token. Set the `Authorization`
header **inside the interceptor** (not the `headers` thunk) so the replay picks up
the fresh token rather than the stale one baked into the original request.

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

const rpc = createRpcClient({ baseUrl: "/rpc", interceptors: [authRefresh] });
```

Guard against a refresh loop in your own code (e.g. cap to one replay, or have
`refreshToken` reject when the refresh token itself is dead): the interceptor
will rethrow a second `401` to `onError` / the call site rather than retry
forever. For **cookie/session** auth there's no client-held token to refresh:
let the server manage session lifetime (e.g. Phoenix's session token already
expires and reissues), and on a `401` send the user to log in rather than
attempting an in-band refresh.

## Raw untyped client

If you need to call procedures without generated types, `createClient` returns
a low-level `client.call(procedure, input, init?)`:

```ts
import { createClient } from "@elixir-ts-rpc/client";

const client = createClient({ baseUrl: "/rpc" });
const me = await client.call("auth.me", {});
```
