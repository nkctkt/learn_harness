import { Hono } from "hono";
import type { LinkRepository } from "./links/repository.js";
import { linkRoutes } from "./links/routes.js";

/** ルーティングだけを組み立てる。DB 接続は index.ts / テストが注入する(テスト容易性)。 */
export function createApp(repo: LinkRepository) {
  const app = new Hono();
  app.get("/health", (c) => c.json({ status: "ok", service: "api" }));
  app.route("/", linkRoutes(repo));
  return app;
}
