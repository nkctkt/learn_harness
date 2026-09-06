# Exercise 05 — セキュリティ: テストが守らない経路を、誰が見るか

- Phase: 4
- 日付: 2026-09-07
- PR: phase4/security

## 1. 導入したもの

| 層 | 追加 | 何を検出するか | 検出しないもの | 実行層 |
|---|---|---|---|---|
| SAST | Semgrep 自作ルール 4 本(`policies/semgrep/`)+ `p/default` | 文字列連結 SQL、リクエスト由来 URL の未検証 fetch(taint)、pnpm の供給網設定不備 | 認可ロジックの穴、ビジネスロジック | verify 全体 / CI(`security-ok`) |
| SAST(深い) | CodeQL(js-ts / python / actions、security-extended) | 関数境界を越えるデータフロー | - | Nightly のみ(重い) |
| SCA | Trivy fs(vuln HIGH+、`--ignore-unfixed`)、dependency-review(PR 差分、ライセンス) | lockfile 中の既知 CVE、非互換ライセンス | 未公開の脆弱性、到達可能性 | verify 全体 / CI / Nightly(新規 CVE ドリフト) |
| Secret | Trivy secret、gitleaks(pre-commit、CI 全履歴)、GitHub push protection、guard-secrets(PreToolUse) | 既知フォーマットの鍵 | 未知フォーマット、分割された鍵 | 4 層 |
| 依存衛生 | pnpm `minimumReleaseAge` 7 日 / `trustPolicy: no-downgrade` / `blockExoticSubdeps`、Dependabot cooldown 7 日(major 30 日) | (検出ではなく回避)公開直後の悪性版、設定の巻き戻し、URL/git 指定のサブ依存 | 7 日以上気づかれない悪性版 | install 時 / 週次 |
| 運用 | OpenSSF Scorecard、`/add-dependency` skill、`.trivyignore` | リポジトリ運用の健全性、依存追加の手順逸脱 | - | Nightly / Agent |
| コード | enricher `POST /enrich`: `resolve_public_url`(名前解決後の IP で判定)+ `fetch_html`(リダイレクト毎に再検証、1 MB 上限、HTML のみ) | - | - | - |

## 2. 意図的欠陥と検出結果

| # | 欠陥 | 単体テスト | Semgrep(自作) | Trivy | gitleaks(staged) |
|---|---|---|---|---|---|
| 1 | `sql.raw(\`... '${host}'\`)`(文字列連結 SQL) | **33 passed**(守っていない) | ✔ `shelf.drizzle-sql-raw-interpolation` | - | - |
| 2 | FastAPI ハンドラで `client.get(req.url)`(検証なし SSRF) | **通る**(テストが無い経路) | ✔ `shelf.py-ssrf-unvalidated-request`(taint) | - | - |
| 3 | `lodash@4.17.20` を追加 | 通る | - | ✔ HIGH ×2(CVE-2021-23337、CVE-2026-4800、修正版あり) | - |
| 4 | `ghp_` で始まる架空トークン | 通る | - | ✔ CRITICAL `github-pat` | **✘ no leaks found** |

観察:

- **#1 と #2 は Phase 3 で「まだ検出手段なし」だったもの。** テストは書いた経路しか守らない。SAST は書かれた全経路を見るが、パターンに一致するものしか見ない。両方要る。
- **#2 の taint ルールでは、`if (!isPublicHost(...)) return` のような分岐は sanitizer にならない。** 値が sanitizer 関数を通って返ってくる形(`safe = assertPublicUrl(url)`)でないと taint が消えない。これは Semgrep の制約だが、「検証済みの値を別の変数として扱う」設計指針としても正しい。自作ルールの negative fixture を直す過程で学んだ。
- **#4 は gitleaks が見逃し、Trivy が拾った。** 架空値を `aBcDeFgHiJ...0123456789ab` と規則的に作ったため、gitleaks のエントロピー閾値(誤検知抑制)に引っかからなかった。実際の鍵はランダムなのでエントロピーが高く検出される。同じ「github-pat」パターンでもツールごとにフィルタが違う。**秘密情報の層を複数持つ理由は、まさにこの検出範囲のズレにある。**
- **#3 は `minimumReleaseAge` では防げない**(古い版なので)。cooldown は「公開直後の悪性版」対策であり、既知 CVE 対策は SCA の仕事。責務が違う。

## 3. `minimumReleaseAge` を有効にしたら何が起きたか

lockfile を再解決した結果、**この 1 週間で入れた依存 5 件が「公開 7 日未満」で拒否された**。

| パッケージ | 拒否された版(公開日) | 採用した版 |
|---|---|---|
| vitest / @vitest/coverage-v8 | 5.0.0(09-03) | 4.1.11(08-18) |
| typescript-eslint | 8.69.0(08-31) | 8.68.0(08-24) |
| @types/node | 26.4.1(09-01) | 26.4.0 |
| @types/react-dom | 19.2.7(09-03) | 19.2.5 |
| @biomejs/biome | 2.5.12 | 2.5.11 |

- 「最新を入れる」という Agent の既定動作と、cooldown は正面から衝突する。テンプレートでは最初から有効にしておかないと、後から入れた時に大量の downgrade が起きる。
- `pnpm install` は拒否理由(パッケージ名・公開時刻・cutoff)を明示する。Agent が読んで対処できる出力になっている。
- pnpm 11 は install 時に "Verifying lockfile against supply-chain policies" を行い、ポリシー違反の lockfile を拒否する。`trustPolicy: no-downgrade` は依存更新でこれらの設定が緩められるのを防ぐ。

## 4. Semgrep の運用で学んだこと

- **`.semgrep/` という隠しディレクトリに置くとルールも検体も無視される。** `policies/semgrep/` に移した。
- **ルール自体にテストが要る。** `semgrep --test` は、ルールと同名の `.ts` / `.py` にある `// ruleid:` / `// ok:` 注釈を照合する。ルールを追加・変更する PR はこれで回帰を防ぐ。CI の最初のステップにした。
- **検体ファイルは意図的に悪いコードなので、スキャンと Biome lint から除外する。** 除外し忘れると verify が自分の検体で落ちる(実際に落ちた)。
- `p/default` は pnpm の設定不備(`minimumReleaseAge` 未設定、`trustPolicy` 未設定、`blockExoticSubdeps` 未設定)を Blocking で指摘した。汎用ルールセットの価値は「知らなかった設定項目を教えてくれる」ことにもある。

## 5. 層ごとの実行時間(実測、M シリーズ Mac)

| 段 | 時間 | 配置 |
|---|---|---|
| Semgrep rule tests + scan(531 ルール / 86 ファイル) | 約 15 秒 | verify 全体・CI |
| Trivy fs(vuln + secret + misconfig) | 約 5 秒(DB キャッシュ後) | verify 全体・CI・Nightly |
| CodeQL 3 言語 | 数分 | Nightly のみ |

Hook 層(編集ごと)には入れない。全体 verify が 32 秒になり、Stop hook の `--changed` は sec 段を skip する。

## 6. Phase 4 で防げるようになった欠陥

| 欠陥 | Phase 3 | Phase 4 |
|---|---|---|
| 文字列連結 SQL | 検出手段なし | Semgrep で merge 不可 |
| 検証なしの外部 URL 取得 | 検出手段なし | Semgrep(taint)で merge 不可、実装は `fetch_html` に集約 |
| 既知 CVE を持つ依存 | 検出手段なし | Trivy(全体)+ dependency-review(差分)で merge 不可、Nightly でドリフト検出 |
| 公開直後の悪性版 | 検出手段なし | `minimumReleaseAge` で解決自体を拒否 |
| 秘密情報 | 3 層 | 4 層(Trivy secret 追加。エントロピー特性が違う) |
| 存在しないパッケージの追加 | 規約のみ | `/add-dependency` skill で実在確認を手順化(強制ではない) |

## 7. 残課題

- guard-bash がコマンド文字列全体を見るため、skill の本文に「シェルにパイプする導入」と書けなかった(3 件目の誤検知)。テンプレートでは `git commit -F` と Write ツールの使い分けを手順化する。
- `/add-dependency` は手順であって強制ではない。Phase 5 の Conftest/Rego で `package.json` の直接依存 allowlist を機械検査する。
- Trivy の image スキャン(ビルド済み image の OS パッケージ)と Hadolint は Phase 5。
