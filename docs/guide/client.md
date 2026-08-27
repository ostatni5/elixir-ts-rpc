# Using the client

The TypeScript side is [`@elixir-ts-rpc/client`](https://www.npmjs.com/package/@elixir-ts-rpc/client)
plus the `rpc.gen.ts` that [codegen](/guide/codegen-workflow) emits from your
`@spec`s.

The package ships the runtime: `createClient`, `RpcError`, guards, interceptor
types. Codegen wraps `createClient` in a typed `createRpcClient` factory. That
factory carries every input, output, and error type. Import `createRpcClient`
from `rpc.gen.ts`. Import the guards from the package.

Every TypeScript sample on this page is type-checked against a real generated
client at build time. Hover any identifier to see its resolved type.

## Creating a client

```ts twoslash
import { createRpcClient } from "./rpc.gen";

const client = createRpcClient({ baseUrl: "/rpc" });
```

`createRpcClient` and the underlying `createClient` accept these options. The
package exports the type as `ClientOptions`.

| Option         | Type                        | Default            | Notes                                           |
| -------------- | --------------------------- | ------------------ | ----------------------------------------------- |
| `baseUrl`      | `string`                    | —                  | Where the RPC plug is mounted (no query string) |
| `headers`      | `HeadersInit` or a thunk    | `{}`               | Fixed, or resolved before each call             |
| `credentials`  | `RequestCredentials`        | `"same-origin"`    | `"include"` for cross-origin cookies            |
| `signal`       | `AbortSignal`               | —                  | Client-wide abort signal                        |
| `fetch`        | `FetchLike`                 | `globalThis.fetch` | Pass your own fetch (SSR, tests)                |
| `onError`      | `(error, op) => void`       | —                  | Watches failed calls, `RpcError` only           |
| `interceptors` | `readonly RpcInterceptor[]` | `[]`               | Ordered chain that wraps each call              |

## Making calls

Methods are namespaced. Their types come from your `@spec`. A second `init`
argument is optional. Its type is `CallInit`. It holds only
`{ signal, headers }`. The signal is combined with the client signal. So either
one aborts the call. The headers are merged key by key over the client headers.
The options `credentials`, `fetch`, `onError`, and `interceptors` are
client-wide only.

```ts twoslash
import { createRpcClient } from "./rpc.gen";
const client = createRpcClient({ baseUrl: "/rpc" });
const controller = new AbortController();
// ---cut---
const user = await client.users.get({ id: "u_1" });

const scoped = await client.users.get({ id: "u_1" }, { signal: controller.signal });
//    ^?
```

## Jumping to the handler

Every method carries a JSDoc link to the Elixir line it was generated from,
along with the handler MFA. Hover the call in your editor to see it, then follow
it to land on the function. Nothing is wired up on your side. It ships in
`rpc.gen.ts`. See [How it works](/guide/how-it-works#_4-generate-the-typescript-client).

## Catching typed errors

A failure throws an `RpcError`. It carries `code`, `source`
(`"transport" | "framework" | "middleware" | "domain"`), `message`, an optional
`details`, and a `status`. The status is the response's HTTP status. It is `0`
when the call never reached the server. When there is no message, `message` holds
the `code`.

Four guards narrow a caught value:

| Guard                        | Narrows to                                    | Use when                              |
| ---------------------------- | --------------------------------------------- | ------------------------------------- |
| `client.x.y.isError`         | that procedure's declared error union          | at a call site, handling domain logic |
| `isTransportError`           | `"aborted" \| "network_error" \| "transport_error"` | the client minted the error itself |
| `isDomainError`, `isMiddlewareError`, `isFrameworkError` | by `e.source`      | in `onError` or an interceptor         |
| `isRpcError`                 | `RpcError`, with `code` as plain `string`      | you do not care which kind it is      |

The per-procedure guard checks `e.code` at runtime. It compares it to the codes
that procedure declares. Transport codes that the client makes itself are not in
that list. Handle those codes separately. The package exports those three codes
as the readonly tuple `TRANSPORT_ERROR_CODES`.

The three codes differ in status. `aborted` and `network_error` mean the request
never reached the server. Their `status` is `0`. `transport_error` is minted
after a response arrives. It carries that response's real HTTP status.

```ts twoslash
import { createRpcClient } from "./rpc.gen";
const client = createRpcClient({ baseUrl: "/rpc" });
const id = "u_1";
const email = "new@example.com";
// ---cut---
import { isTransportError } from "@elixir-ts-rpc/client";

try {
  await client.users.update({ id, email });
} catch (e) {
  if (client.users.update.isError(e)) {
    switch (e.code) {
      case "email_taken":
        console.error("email already in use:", e.details);
        break;
      case "not_found":
        console.error("user no longer exists");
        break;
    }
  } else if (isTransportError(e)) {
    console.error(`transport failure (${e.code}):`, e.message);
  } else {
    throw e;
  }
}
```

A declared union can also include middleware codes such as `unauthorized`. Leave
those to a central `onError`. With `isRpcError`, always add a `default` branch.

::: warning `details` may be undefined at runtime
The generated detail type only shows what the `@spec` declares. Transport errors
never carry `details`. A server error may leave it out. So read it as
`e.details?.field`.
:::

Handler-side rules: [Errors](/guide/errors).

## Aborting requests

You can pass a signal per call, client-wide, or both. If either one fires, the
call is cancelled.

```ts twoslash
import { createRpcClient } from "./rpc.gen";
const client = createRpcClient({ baseUrl: "/rpc" });
// ---cut---
const controller = new AbortController();
setTimeout(() => controller.abort(), 5_000);

const result = await client.users.list({}, { signal: controller.signal });
```

An aborted call rejects with `code: "aborted"`. An abort is a cancellation, not a
failure. That code does not reach `onError`. An abort can also land while the
response body is read. That becomes `transport_error`, and it does reach
`onError`.

## Headers and credentials

`headers` is a fixed object or a thunk. A thunk runs before each call. Use a
thunk for a token that changes. Cross-origin cookies need
`credentials: "include"`.

```ts twoslash
import { createRpcClient } from "./rpc.gen";
declare function getToken(): Promise<string>;
// ---cut---
const client = createRpcClient({
  baseUrl: "https://api.example.com/rpc",
  credentials: "include", // default is "same-origin"
  headers: async () => ({
    Authorization: `Bearer ${await getToken()}`,
  }),
});
```

## Central error handling

`onError` watches failures in one place: redirects, logging, telemetry. It runs
once per failed call and only does side effects. The call still rejects with the
original error. So per-call `.isError` handling keeps working.

```ts twoslash
import { createRpcClient } from "./rpc.gen";
declare const loginUrl: string;
// ---cut---
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

- It fires only when the rejection is an `RpcError`. An interceptor may throw a
  plain `Error`. Then the call rejects without firing it.
- The `"aborted"` code does not reach `onError`. Domain errors do reach it.
  Filter them out unless you want global logging.
- The hook is called synchronously and is not awaited. A synchronous throw is
  logged and dropped. If an `async` hook rejects, nothing handles that rejection.
- `op.input` is the raw request payload. It may hold credentials or personal
  data. Redact it before you log it.
- It fires only after the whole interceptor chain has run. A call that an
  interceptor recovers never reaches it.

## Interceptors

An interceptor controls the call. `onError` only watches it. Each interceptor
wraps the request. It runs after headers resolve and before the transport. It
gets the request and `next`. Calling `next` runs the interceptors after it.
Interceptors are awaited. You can change the request. You can inspect the
result. You can also catch a failure, await async work, and replay via `next`.
The first interceptor in the array wraps all the others.

```ts twoslash
import { createRpcClient } from "./rpc.gen";
// ---cut---
import type { RpcInterceptor } from "@elixir-ts-rpc/client";

const logging: RpcInterceptor = async (req, next) => {
  const started = performance.now();
  const res = await next(req);
  console.debug(`RPC ${req.procedure} ok in ${performance.now() - started}ms`);
  return res;
};

const client = createRpcClient({ baseUrl: "/rpc", interceptors: [logging] });
```

### Auth refresh, with single-flight

The `headers` thunk runs ahead of the call. It cannot help when a token expires
mid-flight. An interceptor can. It catches the `401`, refreshes once for all
in-flight calls, and replays with the new token. Set `Authorization` inside the
interceptor, not in the `headers` thunk. Only then does the replay use the fresh
token.

```ts twoslash
import { createRpcClient } from "./rpc.gen";
declare function getToken(): string;
declare function refreshToken(): Promise<void>;
// ---cut---
import { isMiddlewareError, type RpcInterceptor } from "@elixir-ts-rpc/client";

let refreshing: Promise<void> | null = null; // one refresh, many waiters

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

Limit how many times you replay. Or reject in `refreshToken` once the refresh
token is dead. Otherwise a second `401` loops forever and never reaches the call
site.

With cookie or session auth, the client holds no token to refresh. Let the server
own the session lifetime. On a `401`, send the user to log in. The
[Phoenix example](/guide/examples) uses session auth. It shows a logging
interceptor and an `onError` that filters by source.

## Raw untyped client

`createClient` gives you a low-level `client.call(procedure, input, init?)`. Use
it for procedures that have no generated types:

```ts twoslash
import { createClient } from "@elixir-ts-rpc/client";

const client = createClient({ baseUrl: "/rpc" });
const me = await client.call<Record<string, never>, { id: number }>("auth.me", {});
```

`call<I, O>` takes type arguments. Without them the result is `unknown`.

`rpcMethod` writes a typed method by hand for one such procedure. You pass the
client, the procedure name, and its declared codes. You get an
`RpcMethod<I, O, E>`. It is callable as `(input, init?)` and carries `.isError`.
That guard matches `e.code` against the codes you passed.

```ts twoslash
import { createClient, type RpcError, rpcMethod } from "@elixir-ts-rpc/client";

const client = createClient({ baseUrl: "/rpc" });

const getUser = rpcMethod<{ id: number }, { name: string }, RpcError<"not_found">>(
  client,
  "users.get",
  ["not_found"],
);

const user = await getUser({ id: 1 });
```

## Building your own framework adapter

The client is framework-free. Three exports let you wrap it for another library:

- `buildProxy(client, makeLeaf)` swaps every procedure for a leaf you define.
- `deriveKey(path, input?)` builds the key `[...path, input]`. With no input it
  builds `[...path]`.
- `isRpcMethod(value)` checks for a generated procedure leaf.

`buildProxy` returns `unknown`. So an adapter is not type-safe on its own. Your
adapter must declare its own mapped type over the client. It casts the result to
that type. That is how `@elixir-ts-rpc/react` keeps its types.
