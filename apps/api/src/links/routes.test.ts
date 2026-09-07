import { describe, expect, it } from "vitest";
import { createApp } from "../app.js";
import type { Link } from "../db/schema.js";
import { noopEnricher, noopShortener } from "./clients.js";
import type { LinkRepository } from "./repository.js";

/** 単体テスト: DB を持たないインメモリ実装で HTTP 層の振る舞いだけを検証する。 */
function memoryRepo(): LinkRepository & { rows: Link[] } {
  const rows: Link[] = [];
  return {
    rows,
    list() {
      return Promise.resolve([...rows].reverse());
    },
    findByHref(href) {
      return Promise.resolve(rows.find((r) => r.href === href));
    },
    create(input) {
      const row: Link = {
        id: rows.length + 1,
        href: input.href,
        host: input.host,
        title: input.title ?? null,
        shortCode: input.shortCode ?? null,
        createdAt: new Date(),
      };
      rows.push(row);
      return Promise.resolve(row);
    },
  };
}

const post = (app: ReturnType<typeof createApp>, body: unknown) =>
  app.request("/links", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });

describe("POST /links", () => {
  it("creates a link and returns 201", async () => {
    const app = createApp({ repo: memoryRepo(), enricher: noopEnricher, shortener: noopShortener });
    const res = await post(app, { url: "https://Example.com/x#y", title: "Ex" });
    expect(res.status).toBe(201);
    const { item } = (await res.json()) as { item: Link };
    expect(item).toMatchObject({
      href: "https://example.com/x",
      host: "example.com",
      title: "Ex",
      shortCode: null,
    });
    expect(typeof item.id).toBe("number");
  });

  it("returns the existing row instead of duplicating", async () => {
    const app = createApp({ repo: memoryRepo(), enricher: noopEnricher, shortener: noopShortener });
    await post(app, { url: "https://example.com/x" });
    const res = await post(app, { url: "https://example.com/x#again" });
    expect(res.status).toBe(200);
  });

  it.each([
    [{ url: "javascript:alert(1)" }, "unsupported protocol"],
    [{ url: "http://127.0.0.1:8080/admin" }, "host is not public"],
    [{ url: "http://169.254.169.254/latest/meta-data" }, "host is not public"],
    [{ url: "http://172.25.0.1/" }, "host is not public"],
    [{ url: "http://[fe80::1]/" }, "host is not public"],
    [{ url: "https://example.com/x", title: "" }, "invalid body"],
    [{ url: "https://example.com/x", title: "   " }, "invalid body"],
    [{ url: "https://example.com/x", title: "a".repeat(201) }, "invalid body"],
    [{ title: "no url" }, "invalid body"],
    ["not json", "invalid body"],
  ])("rejects %j with 400", async (body, message) => {
    const app = createApp({ repo: memoryRepo(), enricher: noopEnricher, shortener: noopShortener });
    const res = await (typeof body === "string"
      ? app.request("/links", { method: "POST", body })
      : post(app, body));
    expect(res.status).toBe(400);
    expect(((await res.json()) as { error: string }).error).toContain(message);
  });
});

describe("POST /links with enricher and shortener", () => {
  it("fills the title from the enricher when the client did not send one, and stores the short code", async () => {
    const app = createApp({
      repo: memoryRepo(),
      enricher: { enrich: () => Promise.resolve({ title: "From enricher" }) },
      shortener: { shorten: () => Promise.resolve("abc2345") },
    });
    const res = await post(app, { url: "https://example.com/e" });
    const { item } = (await res.json()) as { item: Link };
    expect(item.title).toBe("From enricher");
    expect(item.shortCode).toBe("abc2345");
  });
  it("keeps a client-provided title and does not call the enricher", async () => {
    let called = 0;
    const app = createApp({
      repo: memoryRepo(),
      enricher: {
        enrich: () => {
          called++;
          return Promise.resolve({ title: "x" });
        },
      },
      shortener: noopShortener,
    });
    const res = await post(app, { url: "https://example.com/e", title: "Mine" });
    expect(((await res.json()) as { item: Link }).item.title).toBe("Mine");
    expect(called).toBe(0);
  });
  it("still creates the link when both services are unavailable", async () => {
    const app = createApp({
      repo: memoryRepo(),
      enricher: { enrich: () => Promise.resolve(undefined) },
      shortener: { shorten: () => Promise.resolve(undefined) },
    });
    const res = await post(app, { url: "https://example.com/e" });
    expect(res.status).toBe(201);
    const { item } = (await res.json()) as { item: Link };
    expect(item.title).toBeNull();
    expect(item.shortCode).toBeNull();
  });
});

describe("GET /links", () => {
  it("lists newest first", async () => {
    const repo = memoryRepo();
    const app = createApp({ repo, enricher: noopEnricher, shortener: noopShortener });
    await post(app, { url: "https://a.example/1" });
    await post(app, { url: "https://a.example/2" });
    const res = await app.request("/links");
    const { items } = (await res.json()) as { items: Link[] };
    expect(items.map((i) => i.href)).toEqual(["https://a.example/2", "https://a.example/1"]);
  });
});
