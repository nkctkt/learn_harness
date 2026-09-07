# Exercise 08 — テストの信頼性と構造: 「テストが通る」の先を測る

- Phase: 7
- 日付: 2026-09-07
- PR: phase7/test-reliability-and-feedback

## 1. 導入したもの

| 種類 | ツール | 何を測るか | 配置 | ゲート? |
|---|---|---|---|---|
| Mutation testing | Stryker(apps/api)、mutmut(enricher) | 実装を機械的に壊した時にテストが落ちる割合(mutation score)。同語反復・assertion 不足を数値化 | Nightly 週次(日曜)、`pnpm --filter @shelf/api test:mutation` / `uv run mutmut run` | No(報告。下がったら人が読む) |
| Architecture rules | dependency-cruiser(TS)、import-linter(Py) | モジュール間の依存方向。循環、routes → db 直結、純粋モジュールからのネットワーク層参照 | verify 全体・CI | **Yes** |
| Dead code | knip | 未使用 export / ファイル / 依存 | verify 全体・CI | No(warn。false positive があり得る) |
| 非決定的レビュー | `test-reviewer` subagent | 「このテストは実装を壊した時に落ちるか」を読んで判断 | Agent が PR 前に呼ぶ | No(助言) |
| フィードバック経路 | `/fix-ci` skill | CI 失敗ログの読み方、再現、禁止事項(skip / 閾値緩和) | Agent | - |
| 修正 | PR 時の Trivy SARIF を HIGH+ に限定 | code scanning の PR コメントが LOW で merge を止めた件(Exercise 07) | security.yml | - |

## 2. Mutation score の初回結果

### apps/api(Stryker、単体テストのみ。結合テストは含まない)

| ファイル | score | 生存 | 未カバー | 読み方 |
|---|---|---|---|---|
| `links/url.ts` | 79% | 14 | 0 | 正規表現の境界(`172.16〜31`)や `.localhost` 等の一部が未検証 |
| `links/routes.ts` | 88% | 3 | 1 | 良好 |
| `links/repository.ts` | 0% | 0 | 11 | **単体テストでは一切実行されない**(結合テストのみが通る)。coverage 0% はテスト不足ではなく設計どおりだが、mutation score は区別しない |
| `app.ts` | 14% → **86%** | 3 → 1 | 3 → 0 | `/health` に **テストが無かった**。`() => undefined` に置き換えても全テストが通っていた |
| 全体 | 70% → **75%** | | | `/health` と route mount のテスト 2 本を追加した結果 |

### services/enricher(mutmut)

| 関数 | 生存 | 読み方 |
|---|---|---|
| `fetch_html` | 28 | リダイレクト・サイズ上限・content-type の境界値が粗い(`>` と `>=`、`MAX_REDIRECTS` の ±1 が区別されていない) |
| `resolve_public_url` | 15 | `BLOCKED_PORTS` の個々の値、`.local` 等のサフィックス個別が未検証 |
| `_MetaParser.handle_endtag` | 7 | `</head>` で読み取りを止める分岐が検証されていない |
| 全体 | 250 中 185 kill、65 生存(74%) | |

観察:

- **coverage 100% でも mutation score は 79%**(`url.ts`)。「行を通った」と「振る舞いを固定した」は違う。Exercise 03 で手作業でやった同語反復の検出が、ここでは自動で数値になる。
- 生存 mutant のほとんどは **境界値**(`>` / `>=`、`±1`、リストの個々の要素)。AI が書きがちな「代表値 1 つだけのテスト」を的確に指す。
- **score をゲートにしない理由**: 生存 mutant には「等価 mutant」(振る舞いが変わらない変異)が混ざり、100% は原理的に無理。閾値を課すと、また同語反復で数字を作りに行く。週次で読んで、下がった箇所だけテストを足す運用にする。
- Stryker は単体テストだけを走らせる設定にした(Testcontainers を mutant ごとに起動すると数十分になる)。`repository.ts` の 0% はその帰結で、DB 層の品質は結合テストが担保する。数字を読む人がこの前提を知らないと誤解する。

## 3. 意図的欠陥と検出結果

| # | 欠陥 | 検出 |
|---|---|---|
| 1 | `links/routes.ts` が `db/client.ts` を直接 import | dependency-cruiser `api-routes-must-not-touch-db`(error) |
| 2 | `enricher/og.py` が `httpx` を import | import-linter「og はネットワーク層を知らない」BROKEN |
| 3 | 未使用ファイル `orphan.ts` + 未使用依存 `left-pad` | knip(Unused files 1、Unused dependencies 1)。warn のみ |
| 4 | `/health` ハンドラを `() => undefined` に変異 | Stryker Survived → テスト追加で Killed |

#1 / #2 は tsc も basedpyright も lint も **何も言わない**(型としては正しい import)。構造の規約は専用のツールでしか守れない。

## 4. 運用で踏んだこと

- **Stryker の vitest runner は pnpm では自動検出されない。** `plugins` に明示する必要があった(strict な node_modules 構造のため)。
- **mutation の生成物(`.stryker-tmp/`、`mutants/`)を全ツールから除外する必要がある。** 除外し忘れると、ESLint が mutant のコードを lint し、Ruff が生成物を整形し、Biome が stats JSON を整形しようとして verify が落ちた(実際に落ちた)。生成物を出すツールを足す時は、gitignore / dockerignore / 各 linter の exclude を同時に触る。
- knip は自分の設定ファイルへの改善ヒント(不要な ignore、冗長な entry)まで出す。初期設定は空に近い方がよい。
- dependency-cruiser の `tsConfig` オプションは repo ルートから相対解決されて `include` が空になった。path alias を使っていないので外した。

## 5. Phase 7 で防げるようになった欠陥

| 欠陥 | Phase 6 | Phase 7 |
|---|---|---|
| 同語反復・境界値欠落のテスト | 規約のみ | 週次の mutation score で可視化、test-reviewer で PR 前に助言 |
| レイヤー違反(routes → db、純粋モジュール → network) | 検出手段なし | dependency-cruiser / import-linter で merge 不可 |
| 未使用 export・依存 | 検出手段なし | knip が警告 |
| CI 失敗の放置・回避 | 記憶頼み | `/fix-ci` に手順と禁止事項 |
| LOW の scanner コメントで merge が止まる | 起きた | PR 時 SARIF を HIGH+ に限定 |

## 6. 残課題

- test-reviewer subagent は定義しただけで、このセッションでは呼び出していない(セッション開始時にロードされるため)。次のセッションで `apps/api/src/app.test.ts` を対象に試す。
- api → enricher / shortener の配線、web のフォーム、Playwright smoke は Phase 7b(別 PR)。
- mutmut は `mutants/` に全ソースのコピーを作る。CI では毎回生成するので実行時間(数分)を観測して、必要なら対象を絞る。

## 7. 追記: ライセンスゲートが新規依存で発火した

この PR で初めて dependency-review の **ライセンス allowlist** が fail した。脆弱性は 0 件。

| 依存 | 経路 | ライセンス | 判断 |
|---|---|---|---|
| `caniuse-lite@1.0.30001810` | dependency-cruiser → browserslist | CC-BY-4.0 | データセットの帰属表示義務のみ。許可に追加 |
| `grimp@3.17` | import-linter | `BSD-2-Clause AND BSD-2-Clause-Views AND BSD-3-Clause` | 複合 SPDX 式。個々は許容範囲なので `BSD-2-Clause-Views` を追加 |

学び:

- ライセンスゲートは「知らない間に GPL が入る」だけでなく、**許容できるが allowlist に無いもの**を止める。止まった時に「なぜこのライセンスなら良いか」を allowlist のコメントに残すのが運用。
- 開発ツール(devDependencies)でも lockfile に入れば対象になる。dependency-review-action は本番 / 開発を区別しない設定にしている(`fail-on-scopes` の既定は runtime のみだが、ここでは両方見たい)。
- 複合 SPDX 式(`A AND B`)は構成要素すべてが allowlist に無いと不許可になる。
