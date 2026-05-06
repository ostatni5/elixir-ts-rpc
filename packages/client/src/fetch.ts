import { RpcError, type RpcErrorPayload, type TransportErrorCode } from "./errors.js";
import type { FetchLike } from "./index.js";

const transport = (code: TransportErrorCode, message: string | undefined, status: number) =>
  new RpcError<TransportErrorCode, unknown, "transport">(
    { code, source: "transport", message },
    status,
  );

export async function doFetch<O>(
  fetchFn: FetchLike,
  url: string,
  input: unknown,
  headers: HeadersInit,
  credentials: RequestCredentials,
  signal: AbortSignal | undefined,
): Promise<O> {
  let response: Response;

  try {
    response = await fetchFn(url, {
      method: "POST",
      headers,
      body: JSON.stringify(input),
      credentials,
      signal,
    });
  } catch (err) {
    if (isAbortError(err)) {
      throw transport("aborted", undefined, 0);
    }
    const message = err instanceof Error ? err.message : String(err);
    throw transport("network_error", message, 0);
  }

  const status = response.status;
  const transportError = (message: string) => transport("transport_error", message, status);

  let json: unknown;
  try {
    json = await response.json();
  } catch {
    throw transportError(response.ok ? "malformed_response" : response.statusText);
  }

  if (!response.ok) {
    const body = json as { error?: RpcErrorPayload };
    if (body?.error?.code) {
      throw new RpcError(body.error, status);
    }
    throw transportError(response.statusText);
  }

  const body = json as { ok?: O };
  if (!Object.hasOwn(body, "ok")) {
    throw transportError("malformed_response");
  }

  return body.ok as O;
}

function isAbortError(err: unknown): boolean {
  return err instanceof Error && err.name === "AbortError";
}
