---
paths:
  - "services/shortener/**"
---

# services/shortener(Go、短縮 URL とクリック集計)

- 応答 JSON は `contracts/shortener.links.response.schema.json` に一致させる。契約テストが読む。フィールド名の変更は api 側(`contracts.ts`)から始める(Exercise 09 の事故)。
- エラーは必ず扱う(`errcheck`)。`nolint` には理由を書く(`nolintlint`)。
- 共有状態(クリック集計)は mutex か atomic。`go test -race` が CI で走る。
- image は distroless、非 root。`Dockerfile` は hadolint と Rego(ルート禁止)が見る。
- 依存追加は `/add-dependency`。`govulncheck` が到達可能な脆弱依存を落とす。
