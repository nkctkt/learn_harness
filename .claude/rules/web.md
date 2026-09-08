---
paths:
  - "apps/web/**"
---

# apps/web(React + Vite + TanStack Query)

- API 呼び出しは `src/lib/api.ts` の型付きクライアント経由のみ。コンポーネントから直接 `fetch` しない(応答の zod 検証をここに集約)。
- SSR は使わない。`/api/*` は dev では Vite の proxy、本番では nginx が api へ流す。
- ロジック(`src/lib/*.ts`)は Vitest で単体テスト。UI は Playwright smoke(`test:e2e`、API はモック)。全サービス結合は compose で人間が確認する。
- `any` 禁止、`noUncheckedIndexedAccess` 有効。配列アクセスは `undefined` を扱う。
