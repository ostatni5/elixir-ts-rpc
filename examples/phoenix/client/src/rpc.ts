import { isDomainError, type RpcInterceptor } from "@elixir-ts-rpc/client";
import { csrfToken } from "./csrf";
import { requestLog } from "./request-log";
import { createRpcClient } from "./rpc.gen";

// Records each call's lifecycle into the request log: a "pending" entry when it
// starts, flipped to "ok"/"error" with a duration when it finishes. Because an
// interceptor wraps `next` and is awaited, it sees both edges of the call,
// something the fire-and-forget `onError` observer can't do.
const logRequests: RpcInterceptor = async (req, next) => {
  const id = requestLog.start(req.procedure);
  const startedAt = performance.now();
  try {
    const res = await next(req);
    requestLog.finish(id, "ok", performance.now() - startedAt);
    return res;
  } catch (error) {
    requestLog.finish(id, "error", performance.now() - startedAt);
    throw error;
  }
};

// Send the CSRF token on every RPC call so Phoenix's `protect_from_forgery`
// accepts our POSTs, the RPC library adds no CSRF mechanism of its own.
export const rpc = createRpcClient({
  baseUrl: "/rpc",
  credentials: "same-origin",
  headers: { "x-csrf-token": csrfToken },
  interceptors: [logRequests],
  // Cross-cutting telemetry: log every transport/framework/middleware failure
  // once, centrally. Domain errors are part of each procedure's contract and
  // are handled at the call site (see App.tsx), so we leave them alone here.
  onError: (error, { procedure }) => {
    if (isDomainError(error)) return;
    console.warn(`RPC ${procedure} failed [${error.source}/${error.code}]: ${error.message}`);
  },
});
