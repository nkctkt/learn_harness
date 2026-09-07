import { describe, expect, it } from "vitest";
import { createApp } from "./app.js";
import { noopEnricher, noopShortener } from "./links/clients.js";
import type { LinkRepository } from "./links/repository.js";

const emptyRepo: LinkRepository = {
  list: () => Promise.resolve([]),
  findByHref: () => Promise.resolve(undefined),
  create: () => Promise.reject(new Error("not used")),
};

describe("GET /health", () => {
  it("reports the service name and status", async () => {
    const res = await createApp({
      repo: emptyRepo,
      enricher: noopEnricher,
      shortener: noopShortener,
    }).request("/health");
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ status: "ok", service: "api" });
  });
  it("mounts link routes at the root", async () => {
    const res = await createApp({
      repo: emptyRepo,
      enricher: noopEnricher,
      shortener: noopShortener,
    }).request("/links");
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ items: [] });
  });
});
