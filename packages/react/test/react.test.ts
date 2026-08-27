import type { Client, DomainError, TransportError } from "@elixir-ts-rpc/client";
import { RpcError, rpcMethod } from "@elixir-ts-rpc/client";
import {
  type QueryKey,
  type SkipToken,
  skipToken,
  type UseMutationResult,
  type UseQueryOptions,
  type UseQueryResult,
  type UseSuspenseQueryOptions,
} from "@tanstack/react-query";
import { describe, expect, expectTypeOf, it, vi } from "vitest";
import {
  createRpcReact,
  type RpcErrorOf,
  type RpcInputOf,
  type RpcOutputOf,
  type RpcReactOptions,
} from "../src/index.js";

type Call = { procedure: string; input: unknown; signal?: AbortSignal };

function recordingClient(output: unknown) {
  const calls: Call[] = [];
  const client: Client = {
    async call<I, O>(procedure: string, input: I, init?: { signal?: AbortSignal }): Promise<O> {
      calls.push({ procedure, input, signal: init?.signal });
      return output as O;
    },
  };
  return { client, calls };
}

type ListInput = { since?: number };
type ListOutput = { users: string[] };
type GetInput = { id: string };
type UpdateInput = { id: string; email: string };
type UpdateOutput = { id: string };
type UpdateError = DomainError<"not_found" | "email_taken">;

function buildClient(output: unknown, options?: RpcReactOptions) {
  const { client, calls } = recordingClient(output);
  const generated = {
    auth: {
      me: rpcMethod<Record<string, never>, { id: string }, never>(client, "auth.me", []),
    },
    users: {
      list: rpcMethod<ListInput, ListOutput, never>(client, "users.list", []),
      get: rpcMethod<GetInput, { id: string }, DomainError<"not_found">>(client, "users.get", [
        "not_found",
      ]),
      update: rpcMethod<UpdateInput, UpdateOutput, UpdateError>(client, "users.update", [
        "not_found",
        "email_taken",
      ]),
    },
  };
  return { rpc: createRpcReact(generated, options), calls };
}

describe("createRpcReact", () => {
  it("mirrors the client namespace tree", () => {
    const { rpc } = buildClient({});
    expect(typeof rpc.auth.me.useQuery).toBe("function");
    expect(typeof rpc.users.list.useQuery).toBe("function");
    expect(typeof rpc.users.update.useMutation).toBe("function");
  });

  it("derives a hierarchical query key from the procedure path + input", () => {
    const { rpc } = buildClient({});
    expect(rpc.users.list.queryKey({ since: 5 })).toEqual(["users", "list", { since: 5 }]);
    expect(rpc.users.list.queryKey()).toEqual(["users", "list"]);
  });

  it("defaults omitted input to {} so a live query key stays a full key", () => {
    const { rpc } = buildClient({});
    expect(rpc.users.list.queryOptions().queryKey).toEqual(["users", "list", {}]);
    expect(rpc.auth.me.queryOptions().queryKey).toEqual(["auth", "me", {}]);
  });

  it("prepends queryKeyPrefix to every derived key", () => {
    const { rpc } = buildClient({}, { queryKeyPrefix: ["tenant", 42] });
    expect(rpc.users.list.queryKey({ since: 5 })).toEqual([
      "tenant",
      42,
      "users",
      "list",
      { since: 5 },
    ]);
    expect(rpc.users.list.queryKey()).toEqual(["tenant", 42, "users", "list"]);
    expect(rpc.users.list.queryOptions().queryKey).toEqual(["tenant", 42, "users", "list", {}]);
  });

  it("keeps the no-arg key a prefix of the full key under a queryKeyPrefix", () => {
    const { rpc } = buildClient({}, { queryKeyPrefix: ["app"] });
    const prefixKey = rpc.users.list.queryKey() as unknown[];
    const fullKey = rpc.users.list.queryKey({ since: 1 }) as unknown[];
    expect(fullKey.slice(0, prefixKey.length)).toEqual(prefixKey);
  });

  it("queryOptions carries our key and a queryFn that forwards the abort signal", async () => {
    const { rpc, calls } = buildClient({ users: ["a"] });
    const options = rpc.users.list.queryOptions({ since: 5 }, { staleTime: 1234 });

    expect(options.queryKey).toEqual(["users", "list", { since: 5 }]);
    expect(options.staleTime).toBe(1234);

    const signal = new AbortController().signal;
    const queryFn = options.queryFn;
    if (typeof queryFn !== "function") throw new Error("queryFn missing");
    const result = await queryFn({ signal, queryKey: options.queryKey, meta: undefined } as never);

    expect(result).toEqual({ users: ["a"] });
    expect(calls).toEqual([{ procedure: "users.list", input: { since: 5 }, signal }]);
  });

  it("user options cannot clobber the derived key or queryFn", () => {
    const { rpc } = buildClient({});
    const options = rpc.users.list.queryOptions({ since: 5 }, {
      queryKey: ["hijacked"],
      staleTime: 1,
    } as never);
    expect(options.queryKey).toEqual(["users", "list", { since: 5 }]);
  });

  it("mutationOptions binds a mutationFn that calls the procedure with its input", async () => {
    const { rpc, calls } = buildClient({ id: "u1" });
    const onSuccess = vi.fn();
    const options = rpc.users.update.mutationOptions({ onSuccess });

    expect(options.onSuccess).toBe(onSuccess);
    const mutationFn = options.mutationFn;
    if (typeof mutationFn !== "function") throw new Error("mutationFn missing");
    const result = await mutationFn(
      { id: "u1", email: "a@b.c" },
      {} as Parameters<typeof mutationFn>[1],
    );

    expect(result).toEqual({ id: "u1" });
    expect(calls).toEqual([
      { procedure: "users.update", input: { id: "u1", email: "a@b.c" }, signal: undefined },
    ]);
  });

  it("re-exposes the procedure's isError guard on the leaf", () => {
    const { rpc } = buildClient({});
    const domain = new RpcError({ code: "not_found", source: "domain" }, 404);
    const transport = new RpcError({ code: "network_error", source: "transport" }, 0);
    expect(rpc.users.update.isError(domain)).toBe(true);
    expect(rpc.users.update.isError(transport)).toBe(false);
  });

  it("types input as required or optional based on the procedure's input shape", () => {
    const { rpc } = buildClient({});
    expectTypeOf<Parameters<typeof rpc.users.get.useQuery>[0]>().toEqualTypeOf<
      GetInput | SkipToken
    >();
    expectTypeOf<Parameters<typeof rpc.users.list.useQuery>[0]>().toEqualTypeOf<
      ListInput | SkipToken | undefined
    >();
  });

  it("flows output and (declared + transport) error types into the hooks", () => {
    const { rpc } = buildClient({});

    expectTypeOf<ReturnType<typeof rpc.users.list.useQuery<ListOutput>>>().toEqualTypeOf<
      UseQueryResult<ListOutput, TransportError>
    >();
    expectTypeOf<ReturnType<typeof rpc.users.update.useMutation>>().toEqualTypeOf<
      UseMutationResult<UpdateOutput, UpdateError | TransportError, UpdateInput, unknown>
    >();
  });

  it("lets select re-type the query data via the TData generic", () => {
    const { rpc } = buildClient({});
    expectTypeOf<ReturnType<typeof rpc.users.list.useQuery<string[]>>>().toEqualTypeOf<
      UseQueryResult<string[], TransportError>
    >();
    expectTypeOf<ReturnType<typeof rpc.users.list.queryOptions<string[]>>>().toEqualTypeOf<
      UseQueryOptions<ListOutput, TransportError, string[], QueryKey>
    >();
  });

  it("infers TData from a select without an explicit type argument", () => {
    const { rpc } = buildClient({ users: ["a"] });
    const options = rpc.users.list.queryOptions({ since: 1 }, { select: (d) => d.users.length });
    expectTypeOf(options).toEqualTypeOf<
      UseQueryOptions<ListOutput, TransportError, number, QueryKey>
    >();
  });

  it("RpcErrorOf names a procedure's declared error union", () => {
    const { rpc } = buildClient({});
    expectTypeOf<RpcErrorOf<typeof rpc.users.update>>().toEqualTypeOf<UpdateError>();
  });

  it("RpcInputOf / RpcOutputOf name a procedure's input and output", () => {
    const { rpc } = buildClient({});
    expectTypeOf<RpcInputOf<typeof rpc.users.update>>().toEqualTypeOf<UpdateInput>();
    expectTypeOf<RpcOutputOf<typeof rpc.users.list>>().toEqualTypeOf<ListOutput>();
  });

  it("queryFilter builds a filter with our key, merging user filter fields", () => {
    const { rpc } = buildClient({});
    expect(rpc.users.list.queryFilter({ since: 5 }, { exact: true })).toEqual({
      exact: true,
      queryKey: ["users", "list", { since: 5 }],
    });
    // No input → the procedure prefix, matching every query under it.
    expect(rpc.users.list.queryFilter()).toEqual({ queryKey: ["users", "list"] });
  });

  it("skipToken disables the query: queryFn is skipToken, key stays stable", () => {
    const { rpc } = buildClient({});
    const options = rpc.users.get.queryOptions(skipToken);
    expect(options.queryFn).toBe(skipToken);
    expect(options.queryKey).toEqual(["users", "get", {}]);
  });

  it("suspenseQueryOptions shares the single-page key and always has a real queryFn", async () => {
    const { rpc, calls } = buildClient({ users: ["a"] });
    const options = rpc.users.list.suspenseQueryOptions({ since: 5 }, { staleTime: 99 });

    // Same key space as queryOptions, so both share one cache entry.
    expect(options.queryKey).toEqual(rpc.users.list.queryOptions({ since: 5 }).queryKey);
    expect(options.staleTime).toBe(99);
    expect(options.queryFn).not.toBe(skipToken);
    expect(typeof options.queryFn).toBe("function");

    const signal = new AbortController().signal;
    const queryFn = options.queryFn;
    if (typeof queryFn !== "function") throw new Error("queryFn missing");
    const result = await queryFn({ signal, queryKey: options.queryKey, meta: undefined } as never);

    expect(result).toEqual({ users: ["a"] });
    expect(calls).toEqual([{ procedure: "users.list", input: { since: 5 }, signal }]);
  });

  it("suspenseQueryOptions defaults omitted input to {} and is assignable to a suspense hook", () => {
    const { rpc } = buildClient({});
    expect(rpc.auth.me.suspenseQueryOptions().queryKey).toEqual(["auth", "me", {}]);

    // The regression this guards: queryOptions is NOT assignable here, because
    // its queryFn admits skipToken, while UseSuspenseQueryOptions excludes it.
    expectTypeOf(rpc.users.list.suspenseQueryOptions({})).toExtend<
      UseSuspenseQueryOptions<ListOutput, never | TransportError, ListOutput, QueryKey>
    >();
  });

  it("suspenseQueryOptions rejects skipToken, unlike queryOptions", () => {
    const { rpc } = buildClient({});
    // @ts-expect-error a suspense query cannot be disabled
    rpc.users.get.suspenseQueryOptions(skipToken);
    // Still fine on the non-suspense variant.
    expect(rpc.users.get.queryOptions(skipToken).queryFn).toBe(skipToken);
  });

  it("infiniteQueryOptions keys a distinct space, folds pageParam into input, forwards signal", async () => {
    const { rpc, calls } = buildClient({ users: ["a"] });
    const options = rpc.users.list.infiniteQueryOptions(
      { since: 0 },
      {
        initialPageParam: 0,
        getNextPageParam: (last) => last.users.length,
        pageInput: (input, cursor) => ({ ...input, since: cursor }),
      },
    );

    expect(options.queryKey).toEqual(["users", "list", "$infinite", { since: 0 }]);

    const signal = new AbortController().signal;
    const queryFn = options.queryFn;
    if (typeof queryFn !== "function") throw new Error("queryFn missing");
    const page = await queryFn({
      pageParam: 7,
      signal,
      queryKey: options.queryKey,
      meta: undefined,
    } as never);

    expect(page).toEqual({ users: ["a"] });
    expect(calls).toEqual([{ procedure: "users.list", input: { since: 7 }, signal }]);
  });

  it("infiniteQueryKey is a separate key space, and carries the queryKeyPrefix", () => {
    const { rpc } = buildClient({});
    expect(rpc.users.list.infiniteQueryKey({ since: 1 })).toEqual([
      "users",
      "list",
      "$infinite",
      { since: 1 },
    ]);
    expect(rpc.users.list.infiniteQueryKey()).toEqual(["users", "list", "$infinite"]);

    const { rpc: scoped } = buildClient({}, { queryKeyPrefix: ["app"] });
    expect(scoped.users.list.infiniteQueryKey({ since: 1 })).toEqual([
      "app",
      "users",
      "list",
      "$infinite",
      { since: 1 },
    ]);
  });
});
