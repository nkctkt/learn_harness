import { Hono } from "hono";
import { z } from "zod";
import type { Enricher, Shortener } from "./clients.js";
import type { LinkRepository } from "./repository.js";
import { isPublicHost, normalizeUrl } from "./url.js";

const createLinkBody = z.object({
  url: z.string(),
  title: z.string().trim().min(1).max(200).optional(),
});

export type LinkDeps = { repo: LinkRepository; enricher: Enricher; shortener: Shortener };

export function linkRoutes({ repo, enricher, shortener }: LinkDeps) {
  const app = new Hono();

  app.get("/links", async (c) => c.json({ items: await repo.list() }));

  app.post("/links", async (c) => {
    const parsed = createLinkBody.safeParse(await c.req.json().catch(() => null));
    if (!parsed.success) return c.json({ error: "invalid body", issues: parsed.error.issues }, 400);

    let normalized: ReturnType<typeof normalizeUrl>;
    try {
      normalized = normalizeUrl(parsed.data.url);
    } catch (e) {
      return c.json({ error: e instanceof Error ? e.message : "invalid url" }, 400);
    }
    if (!isPublicHost(normalized.host)) return c.json({ error: "host is not public" }, 400);

    const existing = await repo.findByHref(normalized.href);
    if (existing) return c.json({ item: existing }, 200);

    // 補助サービスは並列に呼び、どちらが落ちても保存は成功させる(clients.ts が undefined に畳む)
    const [enriched, shortCode] = await Promise.all([
      parsed.data.title ? Promise.resolve(undefined) : enricher.enrich(normalized.href),
      shortener.shorten(normalized.href),
    ]);
    const item = await repo.create({
      ...normalized,
      title: parsed.data.title ?? enriched?.title ?? null,
      shortCode: shortCode ?? null,
    });
    return c.json({ item }, 201);
  });

  return app;
}
