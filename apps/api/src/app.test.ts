import { describe, expect, it } from "vitest";
import { createApp } from "./app.js";
import type { LinkRepository } from "./links/repository.js";

const emptyRepo: LinkRepository = {
  list: () => Promise.resolve([]),
  findByHref: () => Promise.resolve(undefined),
  create: () => Promise.reject(new Error("not used")),
};

describe("GET /health", () => {
  it("reports the service name and status", async () => {
    const res = await createApp(emptyRepo).request("/health");
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ status: "ok", service: "api" });
  });
  it("mounts link routes at the root", async () => {
    const res = await createApp(emptyRepo).request("/links");
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ items: [] });
  });
});
