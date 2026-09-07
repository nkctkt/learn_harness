import { describe, expect, it, vi } from "vitest";
import { httpEnricher, httpShortener } from "./clients.js";

function fakeFetch(status: number, body: unknown) {
  return vi.fn(() =>
    Promise.resolve(
      new Response(JSON.stringify(body), {
        status,
        headers: { "content-type": "application/json" },
      }),
    ),
  ) as unknown as typeof fetch;
}

const warn = () => {
  const calls: string[] = [];
  return { log: { warn: (m: string) => calls.push(m) }, calls };
};

describe("httpEnricher", () => {
  it("returns the title from a well-formed response", async () => {
    const e = httpEnricher({
      baseUrl: "http://enricher",
      fetchFn: fakeFetch(200, { title: "T", image: null }),
    });
    expect(await e.enrich("https://example.com")).toEqual({ title: "T" });
  });
  it("maps a null title to undefined", async () => {
    const e = httpEnricher({
      baseUrl: "http://enricher",
      fetchFn: fakeFetch(200, { title: null }),
    });
    expect(await e.enrich("https://example.com")).toEqual({ title: undefined });
  });
  it("degrades to undefined and warns on http errors", async () => {
    const w = warn();
    const e = httpEnricher({
      baseUrl: "http://enricher",
      fetchFn: fakeFetch(502, { detail: "x" }),
      log: w.log,
    });
    expect(await e.enrich("https://example.com")).toBeUndefined();
    expect(w.calls[0]).toContain("unavailable");
  });
  it("degrades to undefined and warns when the contract changes", async () => {
    const w = warn();
    const e = httpEnricher({
      baseUrl: "http://enricher",
      fetchFn: fakeFetch(200, { pageTitle: "T" }),
      log: w.log,
    });
    expect(await e.enrich("https://example.com")).toBeUndefined();
    expect(w.calls[0]).toContain("unexpected response shape");
  });
  it("posts the url as JSON to /enrich", async () => {
    const f = fakeFetch(200, { title: "T" });
    await httpEnricher({ baseUrl: "http://enricher:8000", fetchFn: f }).enrich(
      "https://example.com/a",
    );
    const [url, init] =
      (f as unknown as { mock: { calls: [URL, RequestInit][] } }).mock.calls[0] ?? [];
    expect(String(url)).toBe("http://enricher:8000/enrich");
    expect(init?.body).toBe(JSON.stringify({ url: "https://example.com/a" }));
  });
});

describe("httpShortener", () => {
  it("returns a well-formed code", async () => {
    const s = httpShortener({
      baseUrl: "http://shortener",
      fetchFn: fakeFetch(201, { code: "abc2345", target: "x" }),
    });
    expect(await s.shorten("https://example.com")).toBe("abc2345");
  });
  it("rejects a code that does not match the shortener's alphabet", async () => {
    const w = warn();
    const s = httpShortener({
      baseUrl: "http://shortener",
      fetchFn: fakeFetch(201, { code: "UPPER-1" }),
      log: w.log,
    });
    expect(await s.shorten("https://example.com")).toBeUndefined();
    expect(w.calls[0]).toContain("unexpected response shape");
  });
});
