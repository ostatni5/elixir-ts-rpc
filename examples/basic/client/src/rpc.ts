import { createRpcClient } from "./rpc.gen";

export const rpc = createRpcClient({ baseUrl: "/rpc" });
