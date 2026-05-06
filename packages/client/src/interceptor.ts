/**
 * The outgoing RPC call as interceptors see it. `headers` is the live, mutable
 * `Headers` instance that will be sent. Set an `Authorization` header on it,
 * including just before a replay so the retried request carries a fresh token.
 * `procedure` and `input` may also be reassigned on the request before `next`.
 */
export type RpcRequest = {
  procedure: string;
  input: unknown;
  headers: Headers;
  signal: AbortSignal | undefined;
};

/**
 * The decoded result of an RPC round-trip, threaded back out through the chain.
 * The value is wrapped so interceptors can read it (logging, metrics) without
 * ambiguity around `undefined`/`null` outputs.
 */
export type RpcResponse = { output: unknown };

/** A unary RPC call: the transport, or the rest of the interceptor chain. */
export type RpcUnary = (req: RpcRequest) => Promise<RpcResponse>;

/**
 * Wraps a unary RPC call. Receives the request and `next`, the rest of the
 * chain, ending in the transport. `await next(req)` to send. It resolves with
 * the {@link RpcResponse} or rejects with an `RpcError`. Catch the rejection to
 * react to failures: an interceptor can `await` a token refresh and call
 * `next(req)` again to replay the call (mutate `req.headers` first). The first
 * interceptor in the `interceptors` array is the outermost wrapper.
 */
export type RpcInterceptor = (req: RpcRequest, next: RpcUnary) => Promise<RpcResponse>;

/**
 * Folds `interceptors` around `endpoint` so that `interceptors[0]` is outermost
 * (sees the request first, the response last). Returns the composed unary call.
 */
export function chainInterceptors(
  interceptors: readonly RpcInterceptor[],
  endpoint: RpcUnary,
): RpcUnary {
  return interceptors.reduceRight<RpcUnary>(
    (next, interceptor) => (req) => interceptor(req, next),
    endpoint,
  );
}
