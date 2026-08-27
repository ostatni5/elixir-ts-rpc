import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";

// Reuses the examples/basic Elixir server (port 4001). Run it first:
//   cd ../../basic/server && mix run --no-halt
export default defineConfig({
  plugins: [react()],
  server: {
    port: 5174,
    proxy: {
      "/rpc": {
        target: "http://localhost:4001",
        changeOrigin: true,
      },
      "/auth": {
        target: "http://localhost:4001",
        changeOrigin: true,
      },
    },
  },
});
