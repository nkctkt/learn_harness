import { serve } from "@hono/node-server";
import { createApp } from "./app.js";
import { createDb, migrateDb } from "./db/client.js";
import { createLinkRepository } from "./links/repository.js";

const databaseUrl = process.env.DATABASE_URL;
if (!databaseUrl) throw new Error("DATABASE_URL is required");

const db = createDb(databaseUrl);
await migrateDb(db);
const app = createApp(createLinkRepository(db));

const port = Number(process.env.PORT ?? 3000);
serve({ fetch: app.fetch, port }, (info) => {
  console.info(`api listening on http://localhost:${info.port}`);
});
