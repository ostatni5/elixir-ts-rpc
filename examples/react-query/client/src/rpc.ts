import { createRpcReact } from "@elixir-ts-rpc/react";
import { createRpcClient } from "./rpc.gen";

// Cookie session set by /auth/login, so send credentials with every RPC call.
const client = createRpcClient({ baseUrl: "/rpc", credentials: "include" });

export const rpc = createRpcReact(client);
