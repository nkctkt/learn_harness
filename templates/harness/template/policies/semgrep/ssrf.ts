import { Hono } from "hono";

declare function isPublicHost(h: string): boolean;
declare function assertPublicUrl(u: string): string;
const app = new Hono();

app.post("/bad", async (c) => {
  const body = (await c.req.json()) as { url: string };
  // ruleid: shelf.ts-ssrf-unvalidated-fetch
  const res = await fetch(body.url);
  return c.json(await res.json());
});

app.post("/good", async (c) => {
  const body = (await c.req.json()) as { url: string };
  // sanitizer は「値がそこを通る」必要がある。if で弾くだけでは taint は消えない(Semgrep の制約であり設計上の指針でもある)
  const safe = assertPublicUrl(body.url);
  // ok: shelf.ts-ssrf-unvalidated-fetch
  const res = await fetch(safe);
  return c.json(await res.json());
});
