# 自作 Semgrep ルール

汎用ルールセット(`p/default`)で拾えない、このコードベース固有の危険パターンを置く。
ルールを追加したら必ず ルールと同名の `.ts` / `.py` に「検出されるべき例」と「されるべきでない例」を対にして置き、
`semgrep --test policies/semgrep` で検証する(ルール自体のテスト)。

| ルール | 検出するもの | 検出しないもの |
|---|---|---|
| `shelf.drizzle-sql-raw-interpolation` | `sql.raw` への補間・連結 | `sql\`...${x}\``(パラメータ化)、クエリビルダ |
| `shelf.postgres-js-unsafe` | `client.unsafe(...)` | - |
| `shelf.ts-ssrf-unvalidated-fetch` | Hono の `c.req.*` 由来の値を `fetch` に渡す | `isPublicHost` を通した値 |
| `shelf.py-ssrf-unvalidated-request` | FastAPI ハンドラの `req.url` を httpx/requests に渡す | `resolve_public_url` / `fetch_html` 経由 |
