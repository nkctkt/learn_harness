import { describe, expect, it } from "vitest";
import { createApp } from "../app.js";
import type { Link } from "../db/schema.js";
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
    const app = createApp(memoryRepo());
    const res = await post(app, { url: "https://Example.com/x#y", title: "Ex" });
    expect(res.status).toBe(201);
    const { item } = (await res.json()) as { item: Link };
    expect(item.href).toBe("https://example.com/x");
    expect(item.title).toBe("Ex");
  });

  it("returns the existing row instead of duplicating", async () => {
    const app = createApp(memoryRepo());
    await post(app, { url: "https://example.com/x" });
    const res = await post(app, { url: "https://example.com/x#again" });
    expect(res.status).toBe(200);
  });

  it.each([
    [{ url: "javascript:alert(1)" }, "unsupported protocol"],
    [{ url: "http://127.0.0.1:8080/admin" }, "host is not public"],
    [{ url: "http://169.254.169.254/latest/meta-data" }, "host is not public"],
    [{ title: "no url" }, "invalid body"],
    ["not json", "invalid body"],
  ])("rejects %j with 400", async (body, message) => {
    const app = createApp(memoryRepo());
    const res = await (typeof body === "string"
      ? app.request("/links", { method: "POST", body })
      : post(app, body));
    expect(res.status).toBe(400);
    expect(((await res.json()) as { error: string }).error).toContain(message);
  });
});

describe("GET /links", () => {
  it("lists newest first", async () => {
    const repo = memoryRepo();
    const app = createApp(repo);
    await post(app, { url: "https://a.example/1" });
    await post(app, { url: "https://a.example/2" });
    const res = await app.request("/links");
    const { items } = (await res.json()) as { items: Link[] };
    expect(items.map((i) => i.href)).toEqual(["https://a.example/2", "https://a.example/1"]);
  });
});
