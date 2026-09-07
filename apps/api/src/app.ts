import { Hono } from "hono";
import { type LinkDeps, linkRoutes } from "./links/routes.js";

/** ルーティングだけを組み立てる。DB 接続や他サービスのクライアントは index.ts / テストが注入する。 */
export function createApp(deps: LinkDeps) {
  const app = new Hono();
  app.get("/health", (c) => c.json({ status: "ok", service: "api" }));
  app.route("/", linkRoutes(deps));
  return app;
}
