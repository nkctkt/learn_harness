# Exercise 01 — 静的ゲート: Formatter / Linter / Type checker は何をどこで検出するか

- Phase: 1
- 日付: 2026-09-05
- PR: https://github.com/nkctkt/learn_harness/pull/1

## 1. 導入したもの

| ツール | 責務 | 検出できるもの | 検出できないもの | 実行層 |
|---|---|---|---|---|
| Biome format / Ruff format | 意味を変えない整形 | 空白・改行・引用符・セミコロン | 全て(判断を含まない) | Hook(自動修正)/ CI(check) |
| Biome lint / Ruff check | 構文木のパターン検出 | `any`、未使用変数・import、bare except、`shell=True`、close 漏れ、理由なし `type: ignore` | **型が必要なもの**(await 忘れ、any の伝播)、ロジック誤り | Hook(編集ファイル)/ CI(全体) |
| tsc / basedpyright | プログラム全体の型推論 | 型不整合、存在しない API、null 安全、注釈なし引数 | スタイル、`any` の使用そのもの(合法)、危険 API の使用 | Hook(編集パッケージ)/ CI(全体) |
| typescript-eslint(型情報ルールのみ) | 型情報を使う lint | floating promise、unsafe な any 伝播、不要な条件 | 整形、構文パターン(Biome に委譲) | **CI / Stop hook のみ**(遅い) |

責務の違いを一言で言うと、**formatter は「見た目」、linter は「書き方の癖」、type checker は「辻褄」、型情報 lint は「型を知っていれば分かる書き方の癖」**を見る。

## 2. 作った欠陥と検出結果

### TypeScript(`apps/api/src/exercise-defects.ts`)

| # | 欠陥 | Biome | tsc | typescript-eslint |
|---|---|---|---|---|
| 1 | `const untyped: any = JSON.parse("{}")` | ✔ `noExplicitAny` | ✘ 合法な TS | ✔ `no-unsafe-assignment` |
| 2 | `const count: number = "not a number"` | ✘ 型を見ない | ✔ TS2322 | (tsc と同じ型エンジン) |
| 3 | `readFile(path, "utf8");` await 忘れ | **✘ 検出できず** | ✘ 合法な TS | ✔ `no-floating-promises` |
| 4 | 未使用ローカル変数 | ✔ `noUnusedVariables` | ✘(`noUnusedLocals` を有効にすれば可) | - |
| 5 | 未使用 import(`Hono`) | ✔ `noUnusedImports` | - | - |
| 6 | 末尾セミコロン欠落 | ✔ format(自動修正) | - | - |

### Python(`services/enricher/enricher/exercise_defects.py`)

| # | 欠陥 | Ruff | basedpyright |
|---|---|---|---|
| 1 | `subprocess.call(cmd, shell=True)` | ✔ S602(bandit 相当) | ✘ 型は正しい |
| 2 | `port: int = raw`(raw は str) | ✘ 型を見ない | ✔ 型 "str" は "int" に割り当てできません |
| 3 | `open(...).read()` close 漏れ | ✔ SIM115 | ✘ |
| 4 | bare `except:` | ✔ E722 | ✘ |
| 5 | 注釈なし引数 `def silenced(x)` | ✘ | ✔ reportMissingParameterType(strict) |
| 6 | 理由なし `# type: ignore` | ✔ PGH003 | ✘(ignore に従う) |
| 7 | 未使用 `import os` | ✔ F401 | ✔ reportUnusedImport(両方が拾う数少ない例) |

### 観察

- **#3 が本演習の核心。** Biome は `readFile` が Promise を返すことを知らないので await 忘れを検出できない。これは Biome の欠陥ではなく設計上の境界で、型解決を伴う lint はコストが 1 桁違う(Biome 全体 25ms、ESLint 2.2s)。だから型情報 lint は編集ごとの Hook には入れず、全体モード(CI / Stop hook)にだけ置く。
- **Linter と Type checker はほぼ重ならない。** 両方が拾ったのは未使用 import だけ。片方で済ませようとすると必ず穴が開く。
- **`any` は tsc にとって合法。** 「型検査が通った」は「型安全」を意味しない。`noExplicitAny`(Biome)と `no-unsafe-*`(typescript-eslint)で初めて塞がる。AI Agent が型エラーを `any` で握りつぶす典型パターンへの対策はここ。
- **Ruff の S ルールは bandit の主要部分を含む。** 別途 bandit を入れると同じ指摘が 2 回出るだけなので入れない。

## 3. 層ごとの実行(同じ `scripts/verify.sh`、違う範囲)

| 層 | 呼び方 | 範囲 | 所要 | 目的 |
|---|---|---|---|---|
| PostToolUse hook | `verify.sh --fix --files <path>` | 編集した 1 ファイル + そのパッケージの tsc | 1 秒前後 | Agent が直後に自分で直す |
| Stop hook / pre-commit(Phase 2) | `verify.sh --changed` | HEAD からの変更ファイル | 数秒 | 完了宣言の前に全部通す |
| CI | `verify.sh --only ts` / `--only py` | 全体 + 型情報 lint | 10 秒前後 | 回避されていないことの保証 |

CI 側の実行結果(欠陥を含む commit):

```
ts / biome + tsc          fail  10s   ✘ biome check / ✘ tsc (all packages)
py / ruff + basedpyright  fail   8s   ✘ ruff check / ✘ basedpyright
ci-ok                     fail        → required check がこれ 1 つで merge を止める
```

CI の設計上の判断:

- **path filter で言語 job を skip する。** skip された job は required check では成功扱いになる。ただし required check に言語 job を直接登録すると「その job が走らなかった PR」がいつまでも pending になるため、`ci-ok` という集約 job だけを登録する。
- **全 action を commit SHA に固定した。** tag は差し替えられる(tj-actions/changed-files 事件、CVE-2025-30066)。Phase 5 で Rego により機械検査する。
- **Hook と CI は同じ `verify.sh` を呼ぶ。** 「ローカルで通ったのに CI で落ちる」を構造的に防ぐ。

## 4. 途中で得た学び

- **macOS 標準の bash は 3.2 で `mapfile` が無い。** hooks は開発者の端末で動くので、スクリプトの移植性はハーネスの一部。
- **typescript-eslint は TypeScript 7.0(Go 実装)を未サポート。** Vite テンプレートが TS 7 を入れてきたため、全パッケージを 6.0.3 に固定した。「最新テンプレートの既定値」と「ツールチェーンの互換性」は別に検証が要る。
- **Biome の `recommended` に a11y ルールが含まれ、テンプレート同梱の SVG が落ちた。** 抑制ではなく不要ファイルの削除で対応。「lint を黙らせる前に、そのコードは必要か」を先に問う。
- **`pnpm create vite` は oxlint を同梱してくる。** 今回は Biome に統一したが、Rust 製 linter の第 3 の選択肢として記録しておく。

## 5. Phase 1 で防げるようになった欠陥

Phase 0 の baseline(型エラー・`any`・未使用 export がコミットできた)に対して:

| 欠陥 | Phase 0 | Phase 1 |
|---|---|---|
| 型エラー | 手で tsc を打てば分かる | Hook で数秒後に通知、CI で merge 不可 |
| `any` | 検出手段なし | Hook / CI で error |
| await 忘れ | 検出手段なし | CI で error |
| 危険 API(`shell=True`) | 検出手段なし | Hook / CI で error |
| ダミー鍵 | 検出手段なし | **まだ素通り**(push protection は既知パターンのみ。Phase 2 で gitleaks を pre-commit に追加) |

## 6. 残課題

- Stop hook と pre-commit(lefthook)は Phase 2。
- `pnpm -r typecheck` は web の `tsc -b` を含むため、将来パッケージが増えると CI の律速になる。Phase 6 で affected 判定を検討。

## 7. 追記: Hook の穴を実際に踏んだ

`eslint.config.mjs` を Bash の heredoc で書いたため PostToolUse hook(`Edit|Write` matcher)が発火せず、整形されていないファイルをそのまま commit・push してしまった。CI の `biome check` が拾って初めて気づいた。

- Hook は「Agent がそのツールを使った時」しか動かない。回避は容易で、悪意がなくても起きる。
- だから CI が最終防衛線であり、Stop hook(Phase 2)で `--changed` を回して commit 前に全変更を見る。
- `docs/plan.md` の「既知のハーネスの穴」に記録した。
