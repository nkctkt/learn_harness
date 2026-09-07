# Quality Engineering — 何を、なぜ、どこで検査するか

このリポジトリで実際に構築・検証した品質ゲートの体系。各項目の根拠は `docs/exercises/00〜10` にある(番号で参照)。
計画段階の版は `docs/plan.md` にあり、本書はその「実測で修正した版」。

## 1. 分類の軸: 「どの問いに答えるか」

ツール名で分類すると重複と抜けが見えない。ゲートは次の 7 つの問いのどれかに答える。

| 問い | ゲート | 検出できるもの | 検出できないもの(別の問いへ) |
|---|---|---|---|
| **ビルドできるか** | compile / type check | 存在しない API、型不整合、null 安全、import 解決 | ロジック誤り、`any` の使用(合法) |
| **合意した書き方か** | format / lint / architecture rules | スタイル、既知バグパターン、危険 API、レイヤー違反、未使用コード | 意図と実装の乖離、型情報が必要なパターン |
| **意図通りに動くか** | unit / integration / contract / E2E | 仕様違反、リグレッション、DB 制約、サービス間契約、UI 経路 | 書いていない経路、テスト自体の弱さ |
| **テストは信頼できるか** | coverage / mutation / test review | 未実行の行、実装を壊しても落ちないテスト、境界値の欠落 | 仕様の妥当性 |
| **安全か** | SAST / SCA / secret / container / IaC / workflow security | 既知の脆弱パターン、既知 CVE、漏洩鍵、設定不備、CI の乗っ取り経路 | 認可ロジックの穴、未知の脆弱性 |
| **出荷物を信頼できるか** | lockfile / cooldown / SBOM / provenance / policy | 依存の改竄・公開直後の悪性版、ビルド経路、規約違反(SHA 固定等) | 上流メンテナの悪意 |
| **保守し続けられるか** | dependency update / dead code / license | 陳腐化、未使用依存、非互換ライセンス | 設計の妥当性 |

## 2. 各ゲートの責務(実測で分かった境界)

### ビルドできるか

| ツール | 責務 | 実測で分かった境界 |
|---|---|---|
| tsc(TS 6.0) | プログラム全体の型推論 | `any` は合法。`.js` 拡張子無しの import は Vitest では動くが tsc で落ちる(Ex.03) |
| basedpyright strict | 同上 + 注釈なし引数の検出 | 第三者ライブラリの部分的な型(Any)で strict が過剰になる。ファイル単位で理由付きに緩める(Ex.10) |
| go build / go vet | コンパイル + 「ほぼ確実にバグ」(printf 型不一致等) | `go test` は vet の一部を内蔵し、vet 違反があるとテスト自体が build failed になる(Ex.07) |

### 合意した書き方か

| ツール | 責務 | 実測で分かった境界 |
|---|---|---|
| Biome / Ruff / gofmt | 整形(判断を含まない。Hook で自動修正してよい) | 生成物(contracts JSON、mutation 生成物)を対象に入れると drift や誤検出になる(Ex.08, 10) |
| Biome lint / Ruff check / golangci-lint | 構文木のパターン。`any`、未使用、bare except、`shell=True`、errcheck、gosec | **型が必要なものは見えない**: `readFile()` の await 忘れを Biome は検出できない(Ex.01) |
| typescript-eslint(型情報ルールのみ) | floating promise、unsafe な any 伝播 | 遅い(Biome の 100 倍)。全体モードのみ(Ex.01) |
| dependency-cruiser / import-linter | モジュール依存の方向(routes → db 禁止、純粋モジュール → network 禁止、循環) | tsc も basedpyright も lint も、型として正しい import には何も言わない(Ex.08) |
| knip | 未使用 export / ファイル / 依存 | false positive があり得るので warn(Ex.08) |

### 意図通りに動くか

| 種類 | 責務 | 実測で分かった境界 |
|---|---|---|
| 単体(fake 注入) | HTTP 層・純粋関数の振る舞い。ミリ秒 | DB 制約、サービス間契約は見えない(Ex.04, 09) |
| 結合(Testcontainers) | 本物の Postgres でマイグレーション・unique 制約・SQL メタ文字 | 数秒 + Docker。Hook 層には重い。全体モードのみ(Ex.04) |
| 契約(consumer の zod → JSON Schema → producer のテスト) | 応答の形の合意 | consumer が 1 つだから成り立つ単純化(Ex.10) |
| E2E(Playwright、API モック) | ブラウザ → React → fetch の経路 | サービス結合は見ない。全サービス E2E は compose で手動(Ex.09) |
| `-race`(Go) | 実行時のデータ競合 | 静的には分からない。テストは通り、vet も lint も静か(Ex.07) |

### テストは信頼できるか

| 種類 | 責務 | 実測で分かった境界 |
|---|---|---|
| coverage | 実行された行 | 同語反復テストでも 100% になる(Ex.03)。**報告のみ。閾値をゲートにしない** |
| mutation(Stryker / mutmut) | 実装を壊した時にテストが落ちる割合 | 生存 mutant の大半は境界値。等価 mutant があるので 100% は無理。週次で読む(Ex.08) |
| test-reviewer(subagent) | 「実装を壊した時にこのテストは落ちるか」を読んで判断 | 非決定的。助言としてのみ。実行 13 分でバグ 1 件を発見(Ex.10) |

### 安全か

| 種類 | ツール | 責務 | 実測で分かった境界 |
|---|---|---|---|
| SAST | Semgrep(自作 taint + p/default) | 文字列連結 SQL、未検証 URL の fetch、設定不備 | パターンに一致するものだけ。sanitizer は「値が通る」形でないと消えない(Ex.05) |
| SAST(深い) | CodeQL | 関数境界を越えるデータフロー | 数分。Nightly のみ |
| SCA | Trivy fs、dependency-review | lockfile の既知 CVE、ライセンス | `trivy fs` と `trivy image` は別物(ベース image の CVE は image でしか出ない)(Ex.06) |
| SCA(到達可能性) | govulncheck | 実際に呼んでいる脆弱関数 | 未使用なら報告しない。Trivy と判定が違う(Ex.07) |
| Secret | guard-secrets(PreToolUse)/ gitleaks(pre-commit・CI)/ Trivy secret / push protection | 既知フォーマットの鍵 | エントロピー閾値でツールごとに検出が違う(Ex.05)。4 層の理由 |
| Container | Hadolint / Trivy config / Trivy image | 書き方 / 危険設定 / 中身の CVE | 3 つは重ならない(Ex.06) |
| IaC | Trivy config / Conftest(Rego) | 汎用の危険設定 / 組織固有の禁止事項 | `terraform validate` は通る(Ex.06) |
| Workflow | actionlint / zizmor / Rego | 構文 / injection・権限・pin / 組織ルール | YAML 1.1 の `on:` が `"true"` キーになる(Ex.06) |

### 出荷物を信頼できるか

| 種類 | 仕組み | 実測で分かった境界 |
|---|---|---|
| lockfile 固定 | pnpm `saveExact`、Rego で `^` 禁止 | pnpm 11 は `.npmrc` を読まず、`pnpm add` は既存 range を保持する(Ex.00) |
| cooldown | pnpm `minimumReleaseAge` 7 日、Dependabot cooldown | 「最新を入れる」Agent の既定と正面衝突。有効化時に 5 依存が downgrade(Ex.05) |
| install スクリプト | pnpm `allowBuilds`、`--ignore-scripts`、Rego で postinstall 禁止 | 供給網攻撃面の縮小と、image build の失敗回避を兼ねる(Ex.00, 04) |
| SHA 固定 | Rego + zizmor + Dependabot(actions) | tag は差し替えられる(CVE-2025-30066) |
| SBOM / provenance | BuildKit attestation、SLSA provenance、CycloneDX(release.yml) | タグ時のみ。`gh attestation verify` で検証 |

## 3. 配置: 速度 × 信頼度 × バイパス可能性

| 層 | 速度 | 対象 | バイパス | 何を置くか | 何を置かないか |
|---|---|---|---|---|---|
| PostToolUse hook | 秒 | 編集した 1 ファイル + そのパッケージの型 | 可(heredoc は素通り) | format(自動修正)、lint、型 | テスト、型情報 lint、スキャン |
| Stop hook | 十秒 | HEAD からの変更 | 可 | `verify.sh --changed`(変更パッケージのテスト込み) | Docker が要るもの |
| pre-commit(lefthook) | 秒 | staged | 可(`--no-verify`、guard-bash が拒否) | 同上 + gitleaks + shell 構文 | - |
| CI(PR) | 分 | 全体 | **不可**(Rulesets) | 全部 + 契約 + 結合 + image + SAST + SCA + policy | mutation、CodeQL |
| Nightly | 時間 | 全体 | 不可 | CodeQL、mutation、Trivy ドリフト、Scorecard | - |
| Release | 分 | 出荷物 | 不可 | image gate、attestation | - |

原則:

1. **同じスクリプト、違う範囲。** `scripts/verify.sh` を全層から呼ぶ。「ローカルで通るのに CI で落ちる」を構造的に防ぐ。
2. **ゲートとして信頼するのは CI + Rulesets だけ。** Hook と pre-commit は「CI で落ちるまでの時間を縮める」投資。
3. **Merge block は false positive がほぼ無いものだけ。** coverage / mutation / knip は報告。
4. **Hook に入れるのは数秒で返るものだけ。** 遅い Hook は Agent が回避する方向に学習する。
5. **CI と local でツールのバージョンを揃える。** trivy、shellcheck、golangci-lint で実際にズレて落ちた(Ex.05, 06)。

## 4. 優先順位(AI Agent が犯す失敗から逆算)

| Agent の典型的な失敗 | 最初に効くゲート | 導入 Phase |
|---|---|---|
| 存在しない API、型の辻褄合わせ(`any`、`# type: ignore`) | tsc / basedpyright + `noExplicitAny` / `PGH003` | 1 |
| 「テストした」と言うが走っていない | Stop hook = verify、CI required check | 2 |
| 同語反復テスト、代表値 1 つのテスト | mutation、test-reviewer | 7, 8a |
| 秘密情報のコピペ | guard-secrets、gitleaks、push protection | 2 |
| 最新の(公開直後の)依存を入れる | minimumReleaseAge、cooldown | 4 |
| 存在しないパッケージ(slopsquatting) | `/add-dependency` 手順、Rego の完全固定 | 4, 5 |
| 文字列連結 SQL、未検証 URL の取得 | Semgrep 自作ルール | 4 |
| 危険な操作(`git push --force`、`rm -rf`) | permissions.deny + guard-bash | 3 |
| ハーネス自体の改変 | guard-edit(ask)、CODEOWNERS | 3 |
| 使わなくなったヘルパー・依存を残す | knip | 7 |

Phase 1〜4 で 7 割の価値が出る、という計画時の見立ては実測でも変わらなかった。

## 5. 入れなかったもの・報告のみにしたもの

| 候補 | 判断 | 理由 |
|---|---|---|
| coverage 閾値 | 報告のみ | Agent は閾値を満たすための無意味なテストを書く(Ex.03) |
| 複雑度メトリクス | 未導入 | 抑制文化を生むだけで、AI 由来の欠陥とは相関が低い |
| 重複コード検出 | 未導入 | 同上。knip の未使用検出の方が費用対効果が高い |
| bandit | 未導入 | Ruff の `S` ルールと重複 |
| Checkov / osv-scanner | 未導入 | Trivy と重複。二重化はノイズ倍増 |
| 全サービス E2E を CI に | 手動(compose) | 数分・flaky。守れるもの(契約)は契約テストの方が安い(Ex.09) |
| Claude sandbox | 未導入(設計のみ) | pnpm / uv / Docker / gh の宛先を洗い出してからでないと開発が止まる |
