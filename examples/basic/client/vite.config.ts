import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";

export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
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
