import { describe, expect, it, vi } from "vitest";
import { combineSignals, combineSignalsPolyfill } from "../src/abort.js";
import type { Client, RpcInterceptor } from "../src/index.js";
import {
  buildProxy,
  createClient,
  deriveKey,
  isDomainError,
  isFrameworkError,
  isMiddlewareError,
  isRpcError,
  isRpcMethod,
  isTransportError,
  RpcError,
  rpcMethod,
} from "../src/index.js";

function mockFetch(status: number, body: unknown, contentType = "application/json") {
  return vi.fn(async (_url: string, _init?: RequestInit): Promise<Response> => {
    const bodyText = typeof body === "string" ? body : JSON.stringify(body);
    return new Response(bodyText, {
      status,
      headers: { "Content-Type": contentType },
    });
  });
}

function rejectingFetch(message: string) {
  return vi.fn(async (): Promise<Response> => {
    throw new TypeError(message);
  });
}

describe("createClient — successful round-trip", () => {
  it("resolves with the `ok` field from the response body", async () => {
    const fetch = mockFetch(200, { ok: { id: 1, name: "Alice" } });
    const client = createClient({ baseUrl: "/rpc", fetch });
    const result = await client.call("users.get", { id: 1 });
    expect(result).toEqual({ id: 1, name: "Alice" });
  });

  it("sends POST with JSON body and Content-Type header", async () => {
    const fetch = mockFetch(200, { ok: null });
    const client = createClient({ baseUrl: "/rpc", fetch });
    await client.call("noop", { foo: "bar" });
    expect(fetch).toHaveBeenCalledOnce();
    const [url, init] = fetch.mock.calls[0] as [string, RequestInit];
    expect(url).toBe("/rpc/noop");
    expect(init.method).toBe("POST");
    expect(init.body).toBe(JSON.stringify({ foo: "bar" }));
    expect(new Headers(init.headers as HeadersInit).get("content-type")).toBe("application/json");
  });
});

describe("createClient — error envelopes", () => {
  it("throws RpcError for 4xx error envelope", async () => {
    const fetch = mockFetch(422, {
      error: { code: "validation_error", message: "bad input", details: { field: "email" } },
    });
    const client = createClient({ baseUrl: "/rpc", fetch });
    await expect(client.call("users.create", {})).rejects.toMatchObject({
      code: "validation_error",
      message: "bad input",
      details: { field: "email" },
      status: 422,
    });
  });

  it("throws RpcError for 5xx with non-JSON body", async () => {
    const fetch = vi.fn(async (): Promise<Response> => {
      return new Response("Internal Server Error", {
        status: 500,
        statusText: "Internal Server Error",
        headers: { "Content-Type": "text/plain" },
      });
    });
    const client = createClient({ baseUrl: "/rpc", fetch });
    await expect(client.call("crash", {})).rejects.toMatchObject({
      code: "transport_error",
      status: 500,
    });
  });

  it("throws RpcError(transport_error, malformed_response) for 2xx with no `ok` field", async () => {
    const fetch = mockFetch(200, { data: "unexpected" });
    const client = createClient({ baseUrl: "/rpc", fetch });
    await expect(client.call("bad", {})).rejects.toMatchObject({
      code: "transport_error",
      message: "malformed_response",
    });
  });
});

describe("createClient — network failure", () => {
  it("throws RpcError(network_error, status 0) when fetch rejects", async () => {
    const fetch = rejectingFetch("Failed to fetch");
    const client = createClient({ baseUrl: "/rpc", fetch });
    await expect(client.call("any", {})).rejects.toMatchObject({
      code: "network_error",
      message: "Failed to fetch",
      status: 0,
    });
  });
});

describe("createClient — abort handling", () => {
  it("per-call signal abort throws RpcError(aborted)", async () => {
    const controller = new AbortController();
    const fetch = vi.fn(async (_url: string, init?: RequestInit): Promise<Response> => {
      return new Promise((_resolve, reject) => {
        init?.signal?.addEventListener("abort", () => {
          const err = new Error("The operation was aborted");
          err.name = "AbortError";
          reject(err);
        });
        controller.abort();
      });
    });
    const client = createClient({ baseUrl: "/rpc", fetch });
    await expect(client.call("slow", {}, { signal: controller.signal })).rejects.toMatchObject({
      code: "aborted",
      status: 0,
    });
  });

  it("client-level signal abort throws RpcError(aborted)", async () => {
    const controller = new AbortController();
    const fetch = vi.fn(async (_url: string, init?: RequestInit): Promise<Response> => {
      return new Promise((_resolve, reject) => {
        init?.signal?.addEventListener("abort", () => {
          const err = new Error("The operation was aborted");
          err.name = "AbortError";
          reject(err);
        });
        controller.abort();
      });
    });
    const client = createClient({ baseUrl: "/rpc", fetch, signal: controller.signal });
    await expect(client.call("slow", {})).rejects.toMatchObject({ code: "aborted", status: 0 });
  });
});

describe("combineSignals polyfill — signal already aborted before call", () => {
  it("throws RpcError(aborted) when client-level signal was already aborted before call", async () => {
    const controller = new AbortController();
    controller.abort();
    const fetch = vi.fn(async (_url: string, init?: RequestInit): Promise<Response> => {
      if (init?.signal?.aborted) {
        const err = new Error("The operation was aborted");
        err.name = "AbortError";
        throw err;
      }
      return new Response(JSON.stringify({ ok: true }), { status: 200 });
    });
    const client = createClient({ baseUrl: "/rpc", fetch, signal: controller.signal });
    await expect(client.call("any", {})).rejects.toMatchObject({
      code: "aborted",
      status: 0,
    });
  });

  it("throws RpcError(aborted) when per-call signal was already aborted before call", async () => {
    const controller = new AbortController();
    controller.abort();
    const fetch = vi.fn(async (_url: string, init?: RequestInit): Promise<Response> => {
      if (init?.signal?.aborted) {
        const err = new Error("The operation was aborted");
        err.name = "AbortError";
        throw err;
      }
      return new Response(JSON.stringify({ ok: true }), { status: 200 });
    });
    const client = createClient({ baseUrl: "/rpc", fetch });
    await expect(client.call("any", {}, { signal: controller.signal })).rejects.toMatchObject({
      code: "aborted",
      status: 0,
    });
  });
});

describe("createClient — headers merging", () => {
  it("merges static headers with per-call headers, per-call wins", async () => {
    const fetch = mockFetch(200, { ok: true });
    const client = createClient({
      baseUrl: "/rpc",
      fetch,
      headers: { "X-Tenant": "acme", "X-Version": "1" },
    });
    await client.call("check", {}, { headers: { "X-Version": "2", "X-Extra": "yes" } });
    const [, init] = fetch.mock.calls[0] as [string, RequestInit];
    const h = new Headers(init.headers as HeadersInit);
    expect(h.get("x-tenant")).toBe("acme");
    expect(h.get("x-version")).toBe("2");
    expect(h.get("x-extra")).toBe("yes");
  });

  it("awaits function-form headers option", async () => {
    const fetch = mockFetch(200, { ok: "done" });
    const getHeaders = vi.fn(async () => ({ Authorization: "Bearer token123" }));
    const client = createClient({ baseUrl: "/rpc", fetch, headers: getHeaders });
    await client.call("secure", {});
    expect(getHeaders).toHaveBeenCalledOnce();
    const [, init] = fetch.mock.calls[0] as [string, RequestInit];
    expect(new Headers(init.headers as HeadersInit).get("Authorization")).toBe("Bearer token123");
  });
});

describe("createClient — credentials", () => {
  it("defaults credentials to `same-origin`", async () => {
    const fetch = mockFetch(200, { ok: null });
    const client = createClient({ baseUrl: "/rpc", fetch });
    await client.call("any", {});
    const [, init] = fetch.mock.calls[0] as [string, RequestInit];
    expect(init.credentials).toBe("same-origin");
  });

  it("respects overridden credentials", async () => {
    const fetch = mockFetch(200, { ok: null });
    const client = createClient({ baseUrl: "/rpc", fetch, credentials: "omit" });
    await client.call("any", {});
    const [, init] = fetch.mock.calls[0] as [string, RequestInit];
    expect(init.credentials).toBe("omit");
  });

  it("supports `include` as an explicit opt-in", async () => {
    const fetch = mockFetch(200, { ok: null });
    const client = createClient({ baseUrl: "/rpc", fetch, credentials: "include" });
    await client.call("any", {});
    const [, init] = fetch.mock.calls[0] as [string, RequestInit];
    expect(init.credentials).toBe("include");
  });
});

describe("createClient — baseUrl joining", () => {
  it("handles trailing slash on baseUrl", async () => {
    const fetch = mockFetch(200, { ok: true });
    const client = createClient({ baseUrl: "/rpc/", fetch });
    await client.call("foo.bar", {});
    expect(fetch.mock.calls[0][0]).toBe("/rpc/foo.bar");
  });

  it("handles leading slash on procedure", async () => {
    const fetch = mockFetch(200, { ok: true });
    const client = createClient({ baseUrl: "/rpc", fetch });
    await client.call("/foo.bar", {});
    expect(fetch.mock.calls[0][0]).toBe("/rpc/foo.bar");
  });

  it("no double slash when both baseUrl has trailing slash and procedure has leading slash", async () => {
    const fetch = mockFetch(200, { ok: true });
    const client = createClient({ baseUrl: "/rpc/", fetch });
    await client.call("/foo.bar", {});
    expect(fetch.mock.calls[0][0]).toBe("/rpc/foo.bar");
  });

  it("throws synchronously when baseUrl contains a query string", () => {
    expect(() =>
      createClient({ baseUrl: "https://api.example.com/rpc?env=dev", fetch: vi.fn() }),
    ).toThrow(/baseUrl must not contain a query string/);
  });

  it("encodes special characters in procedure path segments", async () => {
    const fetch = mockFetch(200, { ok: true });
    const client = createClient({ baseUrl: "/rpc", fetch });
    await client.call("users/get me", {});
    expect(fetch.mock.calls[0][0]).toBe("/rpc/users%2Fget%20me");
  });

  it("preserves plain procedure names unchanged", async () => {
    const fetch = mockFetch(200, { ok: true });
    const client = createClient({ baseUrl: "/rpc", fetch });
    await client.call("users.get", {});
    expect(fetch.mock.calls[0][0]).toBe("/rpc/users.get");
  });
});

describe("combineSignals polyfill — listener cleanup", () => {
  it("removes the listener from the sibling signal after one fires", () => {
    // Exercise the polyfill directly so the assertion holds regardless of
    // whether the runtime has native AbortSignal.any.
    const longLived = new AbortController();
    const perCall = new AbortController();
    const removeSpy = vi.spyOn(longLived.signal, "removeEventListener");

    combineSignalsPolyfill([longLived.signal, perCall.signal]);

    // Aborting the short-lived signal must remove the listener it left on the
    // long-lived one — otherwise listeners accumulate for the client's lifetime.
    perCall.abort();

    expect(removeSpy).toHaveBeenCalledWith("abort", expect.any(Function));
  });

  it("propagates the abort reason of whichever signal fires first", () => {
    const a = new AbortController();
    const b = new AbortController();
    const combined = combineSignalsPolyfill([a.signal, b.signal]);
    const reason = new Error("boom");

    b.abort(reason);

    expect(combined.aborted).toBe(true);
    expect(combined.reason).toBe(reason);
  });

  it("returns undefined when both signals are undefined", () => {
    expect(combineSignals(undefined, undefined)).toBeUndefined();
  });

  it("returns the single signal when only one is provided", () => {
    const ctrl = new AbortController();
    expect(combineSignals(ctrl.signal, undefined)).toBe(ctrl.signal);
    expect(combineSignals(undefined, ctrl.signal)).toBe(ctrl.signal);
  });
});

describe("rpcMethod", () => {
  function fakeClient(call: Client["call"]): Client {
    return { call };
  }

  it("forwards procedure, input, and init to client.call", async () => {
    const call = vi.fn(async () => ({ ok: true }));
    const get = rpcMethod<{ id: string }, { ok: boolean }, RpcError>(
      fakeClient(call as Client["call"]),
      "users.get",
    );
    const init = { signal: new AbortController().signal };

    await get({ id: "1" }, init);

    expect(call).toHaveBeenCalledWith("users.get", { id: "1" }, init);
  });

  it("isError narrows RpcErrors whose code is in the procedure's set, rejects everything else", () => {
    const get = rpcMethod<unknown, unknown, RpcError<"not_found">>(
      fakeClient(vi.fn() as unknown as Client["call"]),
      "users.get",
      ["not_found"],
    );

    expect(get.isError(new RpcError({ code: "not_found", source: "domain" }, 404))).toBe(true);
    expect(get.isError(new Error("plain"))).toBe(false);
    expect(get.isError("nope")).toBe(false);
    expect(get.isError(undefined)).toBe(false);
  });

  it("isError excludes client-synthesized transport/network codes (they are still RpcErrors)", () => {
    const get = rpcMethod<unknown, unknown, RpcError<"not_found">>(
      fakeClient(vi.fn() as unknown as Client["call"]),
      "users.get",
      ["not_found"],
    );

    const network = new RpcError({ code: "network_error", source: "transport" }, 0);
    expect(get.isError(network)).toBe(false);
    expect(get.isError(new RpcError({ code: "transport_error", source: "transport" }, 500))).toBe(
      false,
    );
    expect(get.isError(new RpcError({ code: "aborted", source: "transport" }, 0))).toBe(false);

    // …but they remain RpcErrors, caught by the generic guard.
    expect(isRpcError(network)).toBe(true);
  });
});

describe("isRpcError", () => {
  it("narrows RpcError instances and rejects everything else", () => {
    expect(isRpcError(new RpcError({ code: "not_found", source: "domain" }, 404))).toBe(true);
    expect(isRpcError(new Error("plain"))).toBe(false);
    expect(isRpcError({ code: "not_found", status: 404 })).toBe(false);
    expect(isRpcError("nope")).toBe(false);
    expect(isRpcError(null)).toBe(false);
    expect(isRpcError(undefined)).toBe(false);
  });

  it("recognizes a real thrown error from the client (incl. non-domain codes)", async () => {
    const fetch = rejectingFetch("Failed to fetch");
    const client = createClient({ baseUrl: "/rpc", fetch });

    const err = await client.call("any", {}).catch((e: unknown) => e);

    expect(isRpcError(err)).toBe(true);
    if (isRpcError(err)) {
      // `code` is a plain string here — a synthesized one, not a domain code.
      expect(err.code).toBe("network_error");
    }
  });
});

describe("isTransportError", () => {
  it("narrows the three client-synthesized codes and rejects domain/non-RpcError values", () => {
    expect(isTransportError(new RpcError({ code: "aborted", source: "transport" }, 0))).toBe(true);
    expect(isTransportError(new RpcError({ code: "network_error", source: "transport" }, 0))).toBe(
      true,
    );
    expect(
      isTransportError(new RpcError({ code: "transport_error", source: "transport" }, 500)),
    ).toBe(true);

    expect(isTransportError(new RpcError({ code: "not_found", source: "domain" }, 404))).toBe(
      false,
    );
    expect(isTransportError(new Error("plain"))).toBe(false);
    expect(isTransportError({ code: "network_error" })).toBe(false);
    expect(isTransportError(undefined)).toBe(false);
  });

  it("narrows `code` to the transport union at the type level", () => {
    const e: unknown = new RpcError({ code: "network_error", source: "transport" }, 0);
    if (isTransportError(e)) {
      const code: "aborted" | "network_error" | "transport_error" = e.code;
      expect(code).toBe("network_error");
    }
  });
});

describe("error source category", () => {
  it("carries the server-stamped source through the error envelope", async () => {
    const fetch = mockFetch(404, {
      error: { code: "not_found", source: "domain", message: "gone" },
    });
    const client = createClient({ baseUrl: "/rpc", fetch });
    await expect(client.call("users.get", {})).rejects.toMatchObject({
      code: "not_found",
      source: "domain",
    });
  });

  it("stamps source: 'transport' on client-synthesized failures", async () => {
    const fetch = rejectingFetch("Failed to fetch");
    const client = createClient({ baseUrl: "/rpc", fetch });

    const err = await client.call("any", {}).catch((e: unknown) => e);
    expect(isRpcError(err) && err.source).toBe("transport");
  });

  it("category guards narrow by source and reject other categories", () => {
    const domain = new RpcError({ code: "not_found", source: "domain" }, 404);
    const middleware = new RpcError({ code: "unauthorized", source: "middleware" }, 401);
    const framework = new RpcError({ code: "input_validation_failed", source: "framework" }, 400);

    expect(isDomainError(domain)).toBe(true);
    expect(isMiddlewareError(middleware)).toBe(true);
    expect(isFrameworkError(framework)).toBe(true);

    expect(isDomainError(middleware)).toBe(false);
    expect(isMiddlewareError(framework)).toBe(false);
    expect(isFrameworkError(domain)).toBe(false);
    expect(isDomainError(new Error("plain"))).toBe(false);
    expect(isDomainError({ code: "not_found", source: "domain" })).toBe(false);
  });

  it("narrows a mixed-source union to the matching arm's `code` at the type level", () => {
    type DomainArm = RpcError<"not_found" | "forbidden", undefined, "domain">;
    type MiddlewareArm = RpcError<"unauthorized", undefined, "middleware">;

    // A function param keeps `e` at the full union (a concrete initializer would
    // let TS pre-narrow it to one arm and make the other branch dead code).
    const classify = (e: DomainArm | MiddlewareArm): string => {
      if (isMiddlewareError(e)) {
        const code: "unauthorized" = e.code;
        return code;
      }
      if (isDomainError(e)) {
        const code: "not_found" | "forbidden" = e.code;
        return code;
      }
      return "other";
    };

    expect(
      classify(
        new RpcError<"unauthorized", undefined, "middleware">(
          { code: "unauthorized", source: "middleware" },
          401,
        ),
      ),
    ).toBe("unauthorized");
    expect(
      classify(
        new RpcError<"not_found", undefined, "domain">(
          { code: "not_found", source: "domain" },
          404,
        ),
      ),
    ).toBe("not_found");
  });
});

describe("createClient — onError hook", () => {
  it("fires with (error, { procedure, input }) on a middleware error and the call still rejects", async () => {
    const onError = vi.fn();
    const fetch = mockFetch(401, {
      error: { code: "unauthorized", source: "middleware", message: "nope" },
    });
    const client = createClient({ baseUrl: "/rpc", fetch, onError });
    const input = { id: 1 };

    const err = await client.call("users.get", input).catch((e: unknown) => e);

    expect(err).toBeInstanceOf(RpcError);
    expect(onError).toHaveBeenCalledOnce();
    expect(onError).toHaveBeenCalledWith(err, { procedure: "users.get", input });
  });

  it("fires on a framework error", async () => {
    const onError = vi.fn();
    const fetch = mockFetch(400, {
      error: { code: "input_validation_failed", source: "framework", message: "bad" },
    });
    const client = createClient({ baseUrl: "/rpc", fetch, onError });

    await client.call("users.create", {}).catch(() => {});

    expect(onError).toHaveBeenCalledOnce();
    expect(onError.mock.calls[0]?.[0]).toMatchObject({ source: "framework" });
  });

  it("fires on a domain error (domain reaches the hook)", async () => {
    const onError = vi.fn();
    const fetch = mockFetch(404, {
      error: { code: "not_found", source: "domain", message: "gone" },
    });
    const client = createClient({ baseUrl: "/rpc", fetch, onError });

    await client.call("users.get", {}).catch(() => {});

    expect(onError).toHaveBeenCalledOnce();
    expect(onError.mock.calls[0]?.[0]).toMatchObject({ source: "domain" });
  });

  it("fires on a transport error", async () => {
    const onError = vi.fn();
    const fetch = rejectingFetch("Failed to fetch");
    const client = createClient({ baseUrl: "/rpc", fetch, onError });

    await client.call("any", {}).catch(() => {});

    expect(onError).toHaveBeenCalledOnce();
    expect(onError.mock.calls[0]?.[0]).toMatchObject({ code: "network_error" });
  });

  it("does not fire for an aborted call but the call still rejects", async () => {
    const onError = vi.fn();
    const controller = new AbortController();
    controller.abort();
    const fetch = vi.fn(async (_url: string, init?: RequestInit): Promise<Response> => {
      if (init?.signal?.aborted) {
        const err = new Error("The operation was aborted");
        err.name = "AbortError";
        throw err;
      }
      return new Response("{}", { status: 200 });
    });
    const client = createClient({ baseUrl: "/rpc", fetch, onError });

    await expect(client.call("slow", {}, { signal: controller.signal })).rejects.toMatchObject({
      code: "aborted",
    });
    expect(onError).not.toHaveBeenCalled();
  });

  it("does not fire on a successful round-trip", async () => {
    const onError = vi.fn();
    const fetch = mockFetch(200, { ok: { id: 1 } });
    const client = createClient({ baseUrl: "/rpc", fetch, onError });

    await client.call("users.get", { id: 1 });

    expect(onError).not.toHaveBeenCalled();
  });

  it("re-throws the original error unchanged when the hook runs", async () => {
    const seen: RpcError[] = [];
    const fetch = mockFetch(404, {
      error: { code: "not_found", source: "domain", message: "gone" },
    });
    const client = createClient({
      baseUrl: "/rpc",
      fetch,
      onError: (e) => {
        seen.push(e);
      },
    });

    const err = await client.call("users.get", {}).catch((e: unknown) => e);

    expect(err).toBe(seen[0]);
  });

  it("a throwing hook does not alter the rejection and its failure is logged not propagated", async () => {
    const consoleError = vi.spyOn(console, "error").mockImplementation(() => {});
    const fetch = mockFetch(404, {
      error: { code: "not_found", source: "domain", message: "gone" },
    });
    const client = createClient({
      baseUrl: "/rpc",
      fetch,
      onError: () => {
        throw new Error("hook blew up");
      },
    });

    const err = await client.call("users.get", {}).catch((e: unknown) => e);

    expect(err).toBeInstanceOf(RpcError);
    expect(err).toMatchObject({ code: "not_found", source: "domain" });
    expect(consoleError).toHaveBeenCalled();

    consoleError.mockRestore();
  });
});

describe("createClient — interceptors", () => {
  function tokenAwareFetch() {
    return vi.fn(async (_url: string, init?: RequestInit): Promise<Response> => {
      const authorized = new Headers(init?.headers).get("authorization") === "Bearer fresh";
      const body = authorized
        ? { ok: true }
        : { error: { code: "unauthorized", source: "middleware" } };
      return new Response(JSON.stringify(body), {
        status: authorized ? 200 : 401,
        headers: { "Content-Type": "application/json" },
      });
    });
  }

  it("wraps the call, exposing the request and the decoded output", async () => {
    const fetch = mockFetch(200, { ok: { id: 1 } });
    const seen: Array<{ procedure: string; output: unknown }> = [];
    const tap: RpcInterceptor = async (req, next) => {
      const res = await next(req);
      seen.push({ procedure: req.procedure, output: res.output });
      return res;
    };
    const client = createClient({ baseUrl: "/rpc", fetch, interceptors: [tap] });

    const out = await client.call("users.get", { id: 1 });

    expect(out).toEqual({ id: 1 });
    expect(seen).toEqual([{ procedure: "users.get", output: { id: 1 } }]);
  });

  it("mutates request headers before the transport sends them", async () => {
    const fetch = mockFetch(200, { ok: null });
    const auth: RpcInterceptor = (req, next) => {
      req.headers.set("Authorization", "Bearer t1");
      return next(req);
    };
    const client = createClient({ baseUrl: "/rpc", fetch, interceptors: [auth] });

    await client.call("noop", {});

    const [, init] = fetch.mock.calls[0] as [string, RequestInit];
    expect(new Headers(init.headers).get("authorization")).toBe("Bearer t1");
  });

  it("composes so interceptors[0] is outermost", async () => {
    const fetch = mockFetch(200, { ok: null });
    const order: string[] = [];
    const mk =
      (id: string): RpcInterceptor =>
      async (req, next) => {
        order.push(`>${id}`);
        const res = await next(req);
        order.push(`<${id}`);
        return res;
      };
    const client = createClient({ baseUrl: "/rpc", fetch, interceptors: [mk("a"), mk("b")] });

    await client.call("noop", {});

    expect(order).toEqual([">a", ">b", "<b", "<a"]);
  });

  it("refreshes a token on a 401 and replays the call in-band", async () => {
    let token = "stale";
    const fetch = tokenAwareFetch();
    const refresh = vi.fn(async () => {
      token = "fresh";
    });
    const onError = vi.fn();
    const authRefresh: RpcInterceptor = async (req, next) => {
      req.headers.set("Authorization", `Bearer ${token}`);
      try {
        return await next(req);
      } catch (e) {
        if (isMiddlewareError(e) && e.code === "unauthorized") {
          await refresh();
          req.headers.set("Authorization", `Bearer ${token}`);
          return await next(req);
        }
        throw e;
      }
    };
    const client = createClient({ baseUrl: "/rpc", fetch, interceptors: [authRefresh], onError });

    const out = await client.call("users.get", {});

    expect(out).toBe(true);
    expect(refresh).toHaveBeenCalledOnce();
    expect(fetch).toHaveBeenCalledTimes(2);
    expect(onError).not.toHaveBeenCalled();
  });

  it("single-flights one refresh across concurrent 401s", async () => {
    let token = "stale";
    const fetch = tokenAwareFetch();
    let refreshing: Promise<void> | null = null;
    const refresh = vi.fn(async () => {
      token = "fresh";
    });
    const authRefresh: RpcInterceptor = async (req, next) => {
      req.headers.set("Authorization", `Bearer ${token}`);
      try {
        return await next(req);
      } catch (e) {
        if (isMiddlewareError(e) && e.code === "unauthorized") {
          refreshing ??= refresh().finally(() => {
            refreshing = null;
          });
          await refreshing;
          req.headers.set("Authorization", `Bearer ${token}`);
          return await next(req);
        }
        throw e;
      }
    };
    const client = createClient({ baseUrl: "/rpc", fetch, interceptors: [authRefresh] });

    const results = await Promise.all([
      client.call("a", {}),
      client.call("b", {}),
      client.call("c", {}),
    ]);

    expect(results).toEqual([true, true, true]);
    expect(refresh).toHaveBeenCalledOnce();
    expect(fetch).toHaveBeenCalledTimes(6);
  });

  it("fires onError once only after the chain gives up", async () => {
    const fetch = mockFetch(401, { error: { code: "unauthorized", source: "middleware" } });
    const onError = vi.fn();
    const passthrough: RpcInterceptor = (req, next) => next(req);
    const client = createClient({ baseUrl: "/rpc", fetch, interceptors: [passthrough], onError });

    const err = await client.call("users.get", {}).catch((e: unknown) => e);

    expect(err).toBeInstanceOf(RpcError);
    expect(onError).toHaveBeenCalledOnce();
  });

  it("propagates an error thrown by an interceptor without sending a request", async () => {
    const fetch = mockFetch(200, { ok: null });
    const boom: RpcInterceptor = async () => {
      throw new Error("interceptor boom");
    };
    const client = createClient({ baseUrl: "/rpc", fetch, interceptors: [boom] });

    await expect(client.call("noop", {})).rejects.toThrow("interceptor boom");
    expect(fetch).not.toHaveBeenCalled();
  });
});

describe("adapter core", () => {
  const client: Client = { call: async () => undefined };

  it("isRpcMethod distinguishes generated methods from namespace objects", () => {
    expect(isRpcMethod(rpcMethod(client, "users.list"))).toBe(true);
    expect(isRpcMethod({ list: rpcMethod(client, "users.list") })).toBe(false);
    expect(isRpcMethod(() => undefined)).toBe(false);
    expect(isRpcMethod(null)).toBe(false);
  });

  it("deriveKey appends input, or yields the bare prefix when omitted", () => {
    expect(deriveKey(["users", "list"], { since: 5 })).toEqual(["users", "list", { since: 5 }]);
    expect(deriveKey(["users", "list"])).toEqual(["users", "list"]);
  });

  it("buildProxy replaces each method leaf while preserving namespace shape", () => {
    const generated = {
      auth: { me: rpcMethod(client, "auth.me") },
      users: { list: rpcMethod(client, "users.list") },
    };
    const seen: string[] = [];
    const proxy = buildProxy(generated, (_method, path) => {
      seen.push(path.join("."));
      return { path };
    }) as { auth: { me: { path: string[] } }; users: { list: { path: string[] } } };

    expect(seen.sort()).toEqual(["auth.me", "users.list"]);
    expect(proxy.auth.me.path).toEqual(["auth", "me"]);
    expect(proxy.users.list.path).toEqual(["users", "list"]);
  });
});
