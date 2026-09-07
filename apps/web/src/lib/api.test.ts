import { describe, expect, it, vi } from "vitest";
import { createApi, linkLabel } from "./api";

const json = (status: number, body: unknown) =>
  Promise.resolve(
    new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } }),
  );

describe("createApi", () => {
  it("lists items", async () => {
    const f = vi.fn(() =>
      json(200, {
        items: [
          { id: 1, href: "https://a", host: "a", title: null, shortCode: null, createdAt: "" },
        ],
      }),
    );
    const items = await createApi(f as unknown as typeof fetch).list();
    expect(items).toHaveLength(1);
    expect(f).toHaveBeenCalledWith("/api/links");
  });
  it("returns the created item", async () => {
    const f = vi.fn(() =>
      json(201, {
        item: {
          id: 2,
          href: "https://b",
          host: "b",
          title: "B",
          shortCode: "abc2345",
          createdAt: "",
        },
      }),
    );
    const r = await createApi(f as unknown as typeof fetch).create("https://b");
    expect(r).toMatchObject({ ok: true, item: { shortCode: "abc2345" } });
  });
  it("sends the title only when provided", async () => {
    const f = vi.fn(() =>
      json(201, {
        item: { id: 3, href: "https://c", host: "c", title: "C", shortCode: null, createdAt: "" },
      }),
    );
    const api = createApi(f as unknown as typeof fetch);
    await api.create("https://c", "My title");
    await api.create("https://c");
    const bodies = (f as unknown as { mock: { calls: [string, RequestInit][] } }).mock.calls.map(
      (c) => c[1].body,
    );
    expect(bodies[0]).toBe(JSON.stringify({ url: "https://c", title: "My title" }));
    expect(bodies[1]).toBe(JSON.stringify({ url: "https://c" }));
  });
  it("treats a 2xx without an item as an error", async () => {
    const f = vi.fn(() => json(201, {}));
    expect(await createApi(f as unknown as typeof fetch).create("https://d")).toEqual({
      ok: false,
      error: "http 201",
    });
  });
  it("throws with the status when listing fails", async () => {
    const f = vi.fn(() => json(500, {}));
    await expect(createApi(f as unknown as typeof fetch).list()).rejects.toThrow(
      "list failed: 500",
    );
  });
  it("surfaces the API error message on 400", async () => {
    const f = vi.fn(() => json(400, { error: "host is not public" }));
    const r = await createApi(f as unknown as typeof fetch).create("http://127.0.0.1");
    expect(r).toEqual({ ok: false, error: "host is not public" });
  });
});

describe("linkLabel", () => {
  it("prefers the title, falls back to host, appends the short code", () => {
    expect(linkLabel({ title: "Docs", host: "example.com", shortCode: null })).toBe("Docs");
    expect(linkLabel({ title: "  ", host: "example.com", shortCode: null })).toBe("example.com");
    expect(linkLabel({ title: null, host: "example.com", shortCode: "abc2345" })).toBe(
      "example.com (abc2345)",
    );
  });
});
