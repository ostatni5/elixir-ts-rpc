/**
 * Coarse provenance category, paired with the fine-grained `code`. The server
 * stamps `framework`/`middleware`/`domain` where the error is built (see
 * `RpcElixir.RpcError`), and `transport` is reserved for failures synthesized by
 * this client before any server envelope exists (see `fetch.ts`).
 */
export type RpcErrorSource = "transport" | "framework" | "middleware" | "domain";

export type RpcErrorPayload = {
  code: string;
  source: RpcErrorSource;
  message?: string;
  details?: unknown;
};

/**
 * Codes the client itself synthesizes for failures that never reach the server's
 * error envelope: a closed set the library owns (unlike server-domain codes,
 * which are open). Minted in `fetch.ts`, surfaced as a typed union by
 * `isTransportError`.
 */
export const TRANSPORT_ERROR_CODES = ["aborted", "network_error", "transport_error"] as const;

export type TransportErrorCode = (typeof TRANSPORT_ERROR_CODES)[number];

export class RpcError<
  Code extends string = string,
  Details = unknown,
  Source extends RpcErrorSource = RpcErrorSource,
> extends Error {
  readonly code: Code;
  readonly source: Source;
  readonly details?: Details;
  readonly status: number;

  constructor(payload: RpcErrorPayload, status: number) {
    super(payload.message ?? payload.code);
    this.name = "RpcError";
    this.code = payload.code as Code;
    this.source = payload.source as Source;
    this.details = payload.details as Details | undefined;
    this.status = status;
    // Restore the prototype chain that `extends Error` loses when compiled to
    // ES5-targeted output, so `new.target` keeps `instanceof` correct for subclasses.
    Object.setPrototypeOf(this, new.target.prototype);
  }
}

/**
 * Source-pinned views of {@link RpcError}, paired with the codegen output: a
 * procedure's generated error union is `DomainError<…> | MiddlewareError<…>`, so
 * a `source` check (or an `isDomainError`/`isMiddlewareError` guard) narrows the
 * union, and thus `code`/`details`, at compile time.
 */
export type DomainError<Code extends string = string, Details = unknown> = RpcError<
  Code,
  Details,
  "domain"
>;
export type MiddlewareError<Code extends string = string, Details = unknown> = RpcError<
  Code,
  Details,
  "middleware"
>;
export type FrameworkError<Code extends string = string, Details = unknown> = RpcError<
  Code,
  Details,
  "framework"
>;
export type TransportError = RpcError<TransportErrorCode, unknown, "transport">;
