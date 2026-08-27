import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";

// Backend-integration mode: Phoenix serves the HTML shell (so it can emit the
// CSRF <meta> tag); Vite only builds/serves the React bundle. In dev the shell
// loads modules from this dev server; `vite build` emits a manifest + hashed
// assets into the Phoenix app's priv/static for production.
export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    strictPort: true,
    // The page origin is Phoenix (:4000); modules are loaded cross-origin from
    // here, so advertise this origin and allow CORS for HMR + asset requests.
    origin: "http://localhost:5173",
    cors: true,
  },
  build: {
    manifest: true,
    outDir: "../server/priv/static",
    assetsDir: "assets",
    emptyOutDir: false,
    rollupOptions: { input: "src/main.tsx" },
  },
});
