# Exercise 09 — サービス間の配線と契約: fake が通っても結合は壊れる

- Phase: 7b
- 日付: 2026-09-07
- PR: phase7b/service-wiring-and-e2e

## 1. 導入したもの

| 層 | 追加 | 何を保証するか | 保証しないもの |
|---|---|---|---|
| api | `links/clients.ts`: enricher / shortener の HTTP クライアント。応答は zod で検証、失敗は undefined に畳んで warn | 補助サービスの障害で保存が止まらない。契約不一致を **実行時に** 検出してログに残す | 契約不一致を **CI で** 検出すること |
| api | `POST /links` が title 未指定なら enricher、常に shortener を並列に呼ぶ。`short_code` 列(migration 0001) | - | - |
| web | 型付き API client(`lib/api.ts`)、URL 入力フォーム、一覧に title と short code | UI 層の振る舞い | 実 API との整合 |
| E2E | Playwright(Chromium)。API は `page.route` でモック。CI に path filter 付き job | ブラウザ → React → fetch の経路 | サービス間の結合 |
| compose | api に `ENRICHER_URL` / `SHORTENER_URL`、4 サービスの起動順 | ローカルでの全サービス結合確認(手動) | CI での結合(載せていない) |

## 2. 全サービス結合(compose)の結果

```
POST /links {"url":"https://example.com/"}
→ 201 {"title":"Example Domain","shortCode":"vejzcf2"}   ← enricher が実 URL を取得して title を補完、shortener がコード発行
GET  localhost:8081/vejzcf2 → 302 https://example.com/
api logs: 警告なし
```

## 3. 意図的欠陥: shortener の応答フィールド名を `code` → `short` に変更

| 層 | 結果 | 意味 |
|---|---|---|
| shortener の単体テスト(Go) | **FAIL**(`out["code"]` を見ているため) | producer 側のテストは自分の契約を守る |
| api の単体テスト(fake 使用、45 件) | **全て通る** | consumer 側のテストは fake を見ているので何も気づかない |
| api の型検査・lint・Semgrep | 無反応 | 別プロセスの JSON の形は静的には分からない |
| compose で結合 | `shortCode: null`、api ログに `shortener: unexpected response shape` | zod 検証のおかげで **黙って壊れる** ことは無いが、**人がログを見るまで分からない** |

観察:

- **producer と consumer の両方にテストがあっても、両者が同じ契約を見ている保証はどこにも無い。** 今回は producer のテストが偶然落ちたが、shortener 側が「新フィールドを足して旧フィールドも残す」ような変更なら producer テストも通り、consumer が別のフィールドを読み始めた時に初めて壊れる。
- zod 検証を入れておいたので、不一致は `undefined` + warn に畳まれ、保存は成功した(補助機能の設計方針どおり)。検証が無ければ `item.shortCode` に `undefined` が入って UI が `undefined` を表示するか、TypeScript の型を信じたコードがどこかで例外を投げていた。
- **この穴を CI で塞ぐには契約テストが要る。** 選択肢: (a) shortener / enricher が OpenAPI を公開し、api のクライアントをそこから生成する(型で縛る)、(b) consumer 駆動契約(Pact 等)、(c) api のクライアント zod スキーマを producer 側のテストが読んで自分の応答を検証する(軽量)。Phase 8 で (c) を試す。
- ついでに見えたこと: `https://example.com/contract` は 404 なので enricher が 502 を返し、api は `enricher: unavailable` と warn して title 無しで保存した。障害時の degrade も同じ経路で動いている。

## 4. Playwright の位置づけ

- **API をモックした UI smoke** にした。Chromium 起動込みで 3 秒、CI では path filter で web が変わった時だけ動く。
- 全サービスを立てる E2E は compose で **手動**。CI に載せない理由: Docker 4 コンテナの起動と外部 URL 取得(enricher)が入ると数分かかり flaky になる。それで守れるもの(契約不一致)は契約テストの方が安く確実に守れる。
- `webServer` は `--host 127.0.0.1` を付けないと Vite が IPv6 で待ち受けて Playwright の疎通確認がタイムアウトした。

## 5. 運用で踏んだこと

- `exactOptionalPropertyTypes` により `{ title: undefined }` は `{ title?: string }` に代入できない。「無い」と「undefined」を区別する設計を強制される(良いこと)。
- typescript-eslint `no-misused-promises`: `onSubmit={async fn}` を拒否。`void` で明示的に捨てる形にした。
- `e2e/` と `playwright.config.ts` は tsconfig の対象外なので typescript-eslint の projectService から外した(vitest.config と同じ扱い)。
- knip が `export` された未使用の型(`Logger`、`ApiError`)を指摘。内部型は export しない。

## 6. Phase 7b で防げるようになった欠陥

| 欠陥 | Phase 7 | Phase 7b |
|---|---|---|
| 補助サービス障害で保存が失敗 | (未配線) | 設計で degrade(単体テストで検証) |
| 他サービスの応答の形が変わる | - | 実行時に warn(CI では **未検出**。Phase 8 の契約テスト) |
| UI のフォーム → API → 一覧の経路の退行 | 検出手段なし | Playwright smoke で merge 不可 |
