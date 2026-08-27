// Mounted into the twoslash virtual file system as `rpc.ts`, so react.md
// snippets can `import { rpc } from "./rpc"` exactly as an app would.
import { createRpcReact } from "@elixir-ts-rpc/react";
import { createRpcClient } from "./rpc.gen";

export const rpc = createRpcReact(createRpcClient({ baseUrl: "/rpc" }));
