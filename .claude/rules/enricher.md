---
paths:
  - "services/enricher/**"
---

# services/enricher(FastAPI、URL 取得と OG 解析)

- 外部 URL の取得は `enricher.fetch.fetch_html` だけ。中で `safe_url.resolve_public_url` が名前解決後の IP を検証する(SSRF)。新しい取得経路を作らない(Semgrep `shelf.py-ssrf-unvalidated-request`)。
- 入力は pydantic モデルで境界(`main.py` のハンドラ)に置く。`# type: ignore` 禁止(`PGH003`)。
- HTTP のテストは `respx` でモック。実ネットワークに出るテストを書かない。
- 層は import-linter が守る(`main` → `og` / `fetch` → `safe_url`。逆方向は error)。
- 応答は `contracts/enricher.enrich.response.schema.json` に一致させる。契約テストが読む。
