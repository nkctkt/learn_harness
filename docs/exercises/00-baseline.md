# Exercise 00 — Baseline: ゲートが無い状態で何が素通りするか

- Phase: 0
- 日付: 2026-09-05
- 目的: 以降の Phase で追加する各ゲートの効果を測るための「何も無い状態」を記録する。

## 1. 作った欠陥

使い捨てブランチ `exercise/00-baseline` に `apps/api/src/baseline-defects.ts` を追加した。

```ts
const FAKE_AWS_KEY = "AKIAIOSFODNN7EXAMPLE"; // AWS 公式ドキュメントのサンプル鍵(無効)
export const untyped: any = JSON.parse("{}");
export const count: number = "not a number";
export function unused() { return FAKE_AWS_KEY }
```

| 欠陥 | 種類 | 将来どの層で止まるべきか |
|---|---|---|
| `count: number = "..."` | 型エラー | Hook(編集直後)→ CI の typecheck |
| `: any` | 型の辻褄合わせ(lint) | Hook の Biome `noExplicitAny` → CI |
| `AKIA...EXAMPLE` | 秘密情報らしき文字列 | pre-commit の gitleaks → CI → GitHub push protection |
| `unused()` 未使用 export | dead code | CI の knip(警告) |
| セミコロン欠落・整形 | format | Hook の formatter が自動修正 |

## 2. 実行したこと

```
git checkout -b exercise/00-baseline
git add -A && git commit -m "exercise: baseline defects ..."
→ commit accepted: d31d65f
```

コミットは何にも止められなかった。手で `pnpm typecheck` を打って初めて次が出る。

```
src/baseline-defects.ts(4,14): error TS2322: Type 'string' is not assignable to type 'number'.
```

`any` と秘密情報らしき文字列と未使用 export については、手で打つコマンドすら存在しない。

## 3. 観察

- **検出できる能力とゲートは別物。** tsc は型エラーを検出できるが、誰も実行しなければゲートではない。「Agent がテストしたと言う」と「CI が通る」が別物なのと同じ構造。
- **秘密情報は最も危険で、最も検出手段が無い。** 型エラーは実行時に気づくが、コミットされた鍵は履歴に残り続ける。Phase 4 まで待たず、Phase 1 で gitleaks を pre-commit に入れる価値がある(plan の優先度「最高」の根拠)。
- **リモートが無いので Rulesets も効いていない。** `.github/rulesets/main-protection.json` は用意したが、GitHub に push して `scripts/github/apply-rulesets.sh` を実行するまで宣言に過ぎない。

## 4. Phase 0 で作ったもの

| 成果物 | 状態 |
|---|---|
| pnpm workspace(`apps/api` Hono、`apps/web` Vite+React) | `pnpm -r typecheck`、`pnpm --filter @shelf/web build` が通る。API `/health` 疎通済み |
| `services/enricher`(FastAPI + uv) | `/health` 疎通済み |
| `infra/docker/compose.yaml`(Postgres 17) | `docker compose config` 通過。Phase 3 まで未使用 |
| `AGENTS.md` / `CLAUDE.md` | 47 行 / 7 行 |
| `.github/CODEOWNERS`、`.github/rulesets/main-protection.json`、`scripts/github/apply-rulesets.sh` | 未適用(gh 未導入・リモート未作成) |

## 5. 途中で得た学び(供給網に関するもの)

- **pnpm 11 は依存の install スクリプトを既定で実行しない。** `pnpm-workspace.yaml` の `allowBuilds` に各パッケージの可否を明記するまで `pnpm install` が失敗する。esbuild は postinstall がバイナリ検証だけなので `false` にした。これは「install 時の任意コード実行」という供給網攻撃面への対策で、Phase 4 の `ignore-scripts` の議論を先取りしている。
- **pnpm 11 は pnpm 固有設定を `.npmrc` から読まない。** `saveExact` も `pnpm-workspace.yaml` に書く。さらに `pnpm add` は package.json に既にある range を保持するので、テンプレート由来の `^` は手で外す必要があった。「完全固定にしたつもり」が破れやすい箇所。
- **`pnpm create vite` の最新テンプレートは oxlint を同梱する。** Biome / ESLint と並ぶ第 3 の選択肢。Phase 1 で比較対象に入れる。

## 6. 残作業(ユーザー側の操作が必要)

1. `brew install gh && gh auth login`
2. public リポジトリを作成して push(`gh repo create <name> --public --source=. --push`)
3. `.github/CODEOWNERS` の `@OWNER` を GitHub ユーザー名に置換
4. `scripts/github/apply-rulesets.sh` を実行
5. Settings → Code security で secret scanning と push protection を有効化(public は無償)
6. `main` に直接 push を試み、拒否されることを確認して本ファイルに追記する
