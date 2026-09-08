---
paths:
  - "apps/api/**"
---

# apps/api(Hono + Drizzle + Postgres)

- 入口は `createApp(repo)`(`src/app.ts`)。HTTP 層は `LinkRepository` を注入して DB 無しで単体テストする。結合(`*.integration.test.ts`)は `INTEGRATION=1` で Testcontainers が動く。
- 入力は route の先頭で zod。他サービスの応答は `src/links/clients.ts` の形(zod で検証 → 失敗は `undefined` + log。補助機能で保存を止めない)。
- 応答スキーマ(`src/links/contracts.ts`)を変えたら `contracts/*.schema.json` を再生成し、producer(enricher / shortener)の契約テストを直す。`verify.sh` の `contracts:check` がドリフトを落とす。
- マイグレーションは `schema.ts` を変えて `drizzle-kit generate`。`drizzle/*.sql` は手で書かない(guard-edit が deny)。
- SQL は クエリビルダか `sql\`...${x}\``。`sql.raw` に補間を渡さない(Semgrep `shelf.drizzle-sql-raw-interpolation`)。
- 外部 URL は api から fetch しない。enricher に頼む(SSRF 対策は enricher 側に集約)。
