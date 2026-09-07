import { serve } from "@hono/node-server";
import { createApp } from "./app.js";
import { createDb, migrateDb } from "./db/client.js";
import { httpEnricher, httpShortener, noopEnricher, noopShortener } from "./links/clients.js";
import { createLinkRepository } from "./links/repository.js";

const databaseUrl = process.env.DATABASE_URL;
if (!databaseUrl) throw new Error("DATABASE_URL is required");

const db = createDb(databaseUrl);
await migrateDb(db);
const log = {
  warn: (msg: string, meta?: Record<string, unknown>) => console.warn(msg, meta ?? ""),
};
// 依存サービスの URL が無ければ noop(単体で起動できる)。あれば HTTP 経由で呼ぶ。
const enricher = process.env.ENRICHER_URL
  ? httpEnricher({ baseUrl: process.env.ENRICHER_URL, log })
  : noopEnricher;
const shortener = process.env.SHORTENER_URL
  ? httpShortener({ baseUrl: process.env.SHORTENER_URL, log })
  : noopShortener;
const app = createApp({ repo: createLinkRepository(db), enricher, shortener });

const port = Number(process.env.PORT ?? 3000);
serve({ fetch: app.fetch, port }, (info) => {
  console.info(`api listening on http://localhost:${info.port}`);
});
