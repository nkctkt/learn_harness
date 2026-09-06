import { PostgreSqlContainer, type StartedPostgreSqlContainer } from "@testcontainers/postgresql";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { createApp } from "../app.js";
import { createDb, type Db, migrateDb } from "../db/client.js";
import { createLinkRepository } from "./repository.js";

/**
 * 結合テスト: 本物の Postgres(Testcontainers)でマイグレーション・制約・クエリを検証する。
 * 単体テストのインメモリ実装では再現できないもの(unique 制約、SQL の型、順序)を対象にする。
 * Docker が必要なので verify.sh の全体モード(CI / Stop hook)でのみ実行する。
 */
describe("LinkRepository (postgres)", () => {
  let container: StartedPostgreSqlContainer;
  let db: Db;

  beforeAll(async () => {
    container = await new PostgreSqlContainer("postgres:17-alpine").start();
    db = createDb(container.getConnectionUri());
    await migrateDb(db);
  }, 120_000);

  afterAll(async () => {
    await container.stop();
  });

  it("applies migrations and round-trips a row", async () => {
    const repo = createLinkRepository(db);
    const created = await repo.create({ href: "https://example.com/a", host: "example.com" });
    expect(created.id).toBeGreaterThan(0);
    expect(await repo.findByHref("https://example.com/a")).toMatchObject({ id: created.id });
  });

  it("enforces the unique href constraint at the database level", async () => {
    const repo = createLinkRepository(db);
    // drizzle は DB エラーを "Failed query: ..." で包むので、原因(cause)側の Postgres メッセージを見る
    const err = await repo.create({ href: "https://example.com/a", host: "example.com" }).then(
      () => null,
      (e: unknown) => e,
    );
    expect(err).toBeInstanceOf(Error);
    const cause = (err as Error & { cause?: unknown }).cause;
    expect(String(cause instanceof Error ? cause.message : err)).toMatch(/unique|duplicate/i);
  });

  it("treats SQL metacharacters in input as data, not as SQL", async () => {
    const repo = createLinkRepository(db);
    const app = createApp(repo);
    const hostile = "https://example.com/?q=' OR 1=1; DROP TABLE links; --";
    const res = await app.request("/links", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ url: hostile }),
    });
    expect(res.status).toBe(201);
    // テーブルはまだ存在し、悪意ある文字列が(URL エンコードされて)1 行として保存されている
    const all = await repo.list();
    expect(all.some((r) => decodeURIComponent(r.href).includes("DROP TABLE"))).toBe(true);
  });
});
