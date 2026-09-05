import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";

export default defineConfig({
  plugins: [react()],
  server: {
    proxy: {
      // 開発時は /api/* を Hono に転送する。本番は同一オリジン配信か API Gateway が担う。
      "/api": { target: "http://localhost:3000", rewrite: (p) => p.replace(/^\/api/, "") },
    },
  },
});
