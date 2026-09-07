# 学習プロジェクト計画 — Harness Engineering を実践で学ぶ

- 作成日: 2026-09-05
- 位置づけ: `../ai_driven_development/`(2026-09-03 の調査レポート)の理論を実際に動かして検証し、
  `poc/company-ai-template` を多言語 monorepo 対応の v2 テンプレートに育てる実験場。
- 最優先目的: アプリケーションではなく **Software Quality Engineering と Harness の責務分離を体系的に理解すること**。

## 1. 学習目標

1. **品質チェックの地図を持つ。** ツール名ではなく「どの問いに答えるゲートか」で分類し、新規プロジェクトで取捨選択できる。
2. **信頼境界を設計できる。** Agent 側(CLAUDE.md / Skills / Hooks / Permissions / Sandbox)と Repository 側(pre-commit / CI / Rulesets)を、速度と信頼度のトレードオフで配置できる。
3. **再利用可能なテンプレートに落とす。** TS / Python / Go / React のプロジェクトに数時間で適用できるハーネス一式(`templates/`)。

### 前提の修正(設計判断の根拠)

- 「Agent 側 = 非決定的、CI 側 = 決定的」ではない。Hook の lint も決定的。本当の分かれ目は **バイパスできるか**。
  ローカルで動くものは全て回避可能で、強制力を持つのは **CI + Rulesets(required checks)** だけ。
- 「CI が緑 = 品質担保」でもない。同じ Agent が書いたテストは同語反復になりうる。mutation testing・テストレビュー・プロセス制約で補う。
- チェックの優先度は **AI Agent が実際に犯す失敗**(存在しない API、型の辻褄合わせ、規約不統一、古い依存、秘密情報コピペ、テスト水増し)から逆算する。
- ゲートを増やすほど false positive が増え、抑制コメントで黙らせる文化が生まれる。「無いと何が起きるか」を言えないゲートは入れない。

## 2. 品質エンジニアリングの体系

「何をチェックするか」ではなく「どの問いに答えるか」で分類する。

| 問い | ゲート | 検出できるもの | 検出できないもの |
|---|---|---|---|
| ビルドできるか | compile / type check | 存在しない API、型不整合、null 安全 | ロジック誤り、実行時の外部依存 |
| 合意した書き方か | format / lint / arch rules | スタイル、既知バグパターン、レイヤー違反、未使用コード | 意図と実装の乖離 |
| 意図通りに動くか | unit / integration / E2E / contract | 仕様違反、リグレッション、結合不整合 | 未テスト経路、テスト自体の誤り |
| テストは信頼できるか | coverage / mutation | 未テスト領域、無意味なテスト | 仕様の妥当性 |
| 安全か | SAST / SCA / secret / container / IaC | 既知の脆弱パターン、既知 CVE、漏洩鍵、設定不備 | 認可ロジックの穴、ビジネスロジック脆弱性 |
| 出荷物を信頼できるか | lockfile / pinning / SBOM / provenance / Actions security | 依存改竄、ビルド経路の汚染、CI 乗っ取り | 上流メンテナの悪意 |
| 保守し続けられるか | dependency update / API compat / dead code | 陳腐化、破壊的変更 | 設計の妥当性 |

### ゲート配置表

Hook = Claude Code の PostToolUse/Stop、pre-commit = git hook、CI = PR 時、Nightly = scheduled。

Hook 層の secret scan は依存ゼロの自前スクリプト(`.claude/hooks/guard-secrets.sh`)で行う。PreToolUse なので gitleaks と違い **書き込む前に** 止められる。既知パターンしか見ないので、pre-commit / CI / サーバ側の gitleaks・push protection を代替しない(Phase 2 で lefthook と共に導入)。

| ゲート | ツール | Hook | pre-commit | CI | Nightly | Merge block | コスト | 優先度 |
|---|---|---|---|---|---|---|---|---|
| Format | Biome / Ruff / gofmt | 編集ファイルを自動整形 | staged | check | - | Yes | 秒 | 最高 |
| Lint | Biome / Ruff / golangci-lint | 編集ファイル | staged | 全体 | - | Yes | 秒〜分 | 最高 |
| 型情報 lint | typescript-eslint(type-aware) | - | - | 全体 | - | Yes | 分 | 高 |
| Type check | tsc / basedpyright / go build | 編集パッケージ | 任意 | 全体 | - | Yes | 数十秒 | 最高 |
| Unit test | Vitest / pytest / go test | 関連テスト | - | 全体 | - | Yes | 分 | 最高 |
| Secret scan | 自前 grep(hook)/ gitleaks(pre-commit・CI)/ GitHub push protection | 書込前 block + commit 前 block | staged(最重要) | 全履歴 | - | Yes | 秒 | 最高 |
| SCA | Trivy / dependency-review / Dependabot | - | - | lockfile 変更時 | 毎日 | High 以上 | 秒 | 高 |
| Build | vite build / docker build | - | - | 全体 | - | Yes | 分 | 高 |
| Integration | Testcontainers + Postgres | - | - | 全体 | - | Yes | 分 | 高 |
| Coverage | vitest --coverage / pytest-cov | - | - | 差分を報告 | - | No(報告のみ) | 分 | 中 |
| SAST | Semgrep(差分)/ CodeQL(全体) | - | - | Semgrep | CodeQL | Semgrep: Yes | 分〜十分 | 高 |
| Arch rules | dependency-cruiser / import-linter / depguard | - | - | 全体 | - | Yes | 秒 | 中 |
| Dead code | knip / vulture | - | - | 全体 | - | 警告 | 秒 | 低 |
| Container | Hadolint / Trivy image | - | - | Dockerfile 変更時 | 毎日 | Critical | 分 | 中 |
| IaC | Trivy config + Conftest | - | - | IaC 変更時 | - | High 以上 | 秒 | 中 |
| Actions security | actionlint / zizmor / SHA pin(Rego) | - | - | workflow 変更時 | - | Yes | 秒 | 高 |
| Policy | Conftest / Rego | - | - | 対象変更時 | - | Yes | 秒 | 中 |
| SBOM / provenance | Trivy sbom / attest-build-provenance | - | - | release | - | - | 分 | 低 |
| E2E | Playwright | - | - | smoke | full | smoke: Yes | 十分 | 中 |
| Mutation | Stryker / mutmut | - | - | - | 週次 | No | 時間 | 中 |
| License | dependency-review allow-licenses | - | - | lockfile 変更時 | - | Copyleft | 秒 | 低 |

設計原則:

- 同じチェックが複数層に現れるのは意図的な冗長。対象範囲が違う(編集ファイル → staged → 全体)。ゲートとして信頼するのは CI だけ。
- Merge block は false positive がほぼ無いものだけ。カバレッジ絶対値、複雑度、dead code は block にしない。
- Hook に入れるのは数秒で返るものだけ。遅い Hook は Agent が回避する方向に学習する。

## 3. プロジェクト: Reading Shelf

URL を保存すると Python サービスがメタデータを付与し、Go サービスが短縮リンクとクリック集計を担当する。

```
Browser
  │
  ▼
apps/web (React + Vite + TS) ── Playwright
  │ REST(JSON)
  ▼
apps/api (Hono + TS + Drizzle) ──── Postgres
  │ 内部 HTTP                          ▲
  ├──▶ services/enricher (FastAPI)    │ URL 取得 / OGP 解析 → SSRF・timeout 教材
  └──▶ services/shortener (Go, Ph.6)  ┘ 短縮 URL・クリック集計 → hot path 教材

infra/docker     Dockerfile + compose      → container scan 教材
infra/terraform  validate + scan のみ。apply しない → IaC scan 教材
```

選定理由: セキュリティスキャンが検出する問題(SQLi / SSRF / 認証 / Docker / IaC)が機能要件から自然に発生する。
他候補(経費精算、multi-repo の Todo API)は却下。理由は Python/Go の必然性が無い、またはサービス間結合・monorepo CI が学べないため。

## 4. 技術スタック

| 領域 | 選定 | 主な代替 | 理由 |
|---|---|---|---|
| Monorepo | pnpm workspaces(追加ツール無し) | Turborepo / Nx | まず Actions の path filter で affected を手作りし、必要になれば Turbo |
| TS format/lint(hook 層) | Biome | Prettier + ESLint | 速度と autofix。調査 13.2 の推奨 |
| TS 型情報 lint(CI 層) | typescript-eslint(type-aware ルールのみ) | - | Biome では検出できないもの(floating promise 等)を層差として体験。Exercise 01 で実証済み |
| TS 型 | tsc `strict` + `noUncheckedIndexedAccess`、**TypeScript 6.0.x に固定** | tsgo(TS 7) | typescript-eslint が TS 7 未対応(2026-09)。対応後に tsgo へ移行を検討 |
| TS test | Vitest + Testcontainers | Jest | - |
| TS arch / dead code | dependency-cruiser / knip | eslint-plugin-boundaries / ts-prune | - |
| Frontend | React + Vite + TanStack Query | Next.js | SSR 固有の複雑さを排除 |
| API | Hono + Drizzle + zod | NestJS / Fastify | 薄いのでツール挙動が見やすい |
| Py 管理 | uv | Poetry | lockfile・pin・venv が 1 ツール |
| Py format/lint | Ruff(`S` ルール含む) | Black + flake8 + bandit | bandit は Ruff の S ルールと重複 |
| Py 型 | basedpyright | mypy / ty | 速度と JSON 出力。mypy との差分は演習 |
| Py test | pytest + pytest-cov + httpx + respx | - | - |
| Py arch | import-linter | - | - |
| Go | gofmt / goimports / go vet / golangci-lint / govulncheck / `go test -race` | - | 調査は Go 未対応。本プロジェクトの独自貢献 |
| Secrets | gitleaks(hook / pre-commit)+ GitHub push protection(サーバ) | TruffleHog | 層ごとの役割差 |
| SAST | Semgrep(PR 差分・自作ルール)+ CodeQL(nightly / public 無償) | SonarQube | ルールが読める / データフロー解析 |
| SCA / Container / IaC / SBOM | Trivy 一本 + dependency-review-action | Grype / Checkov / osv-scanner | 二重化はノイズ倍増 |
| Policy | Conftest / Rego | - | SHA pin、未承認依存、Terraform plan |
| Actions | actionlint + zizmor + harden-runner + SHA pin | pinact | - |
| 依存衛生 | Dependabot cooldown 7 日 + pnpm `minimumReleaseAge` + `.npmrc`(`ignore-scripts`, `save-exact`) | Renovate | slopsquatting・公開直後の悪性版 |
| git hooks | lefthook | pre-commit framework / husky | 多言語 monorepo で YAML 1 枚 |
| E2E | Playwright | Cypress | - |
| Mutation | Stryker(TS)/ mutmut(Py) | - | 週次のみ |

## 5. Repository 構成

```
learn_harness/
├── AGENTS.md / CLAUDE.md(@AGENTS.md)       # 200 行未満。Claude 固有分のみ CLAUDE.md
├── .claude/
│   ├── settings.json                        # permissions.deny / sandbox / hooks
│   ├── rules/{api,web,enricher,infra,db}.md # paths 付き領域別ルール
│   ├── skills/                              # new-api / add-dependency / security-review / create-pr / new-service / fix-ci
│   ├── agents/                              # test-reviewer / security-reviewer
│   └── hooks/                               # session-start / guard-bash / guard-edit / post-edit-check / stop-verify
├── .github/
│   ├── workflows/                           # ci.yml / security.yml / iac-policy.yml / nightly.yml / release.yml
│   ├── CODEOWNERS / dependabot.yml / pull_request_template.md
│   └── rulesets/*.json                      # Rulesets as code
├── scripts/
│   ├── verify.sh                            # --changed で差分限定(hook)、既定で全体(CI)
│   └── verify/{ts,py,go,infra}.sh
├── policies/{rego,tests}/
├── apps/{web,api}  services/{enricher,shortener}  packages/shared-types
├── infra/{docker,terraform}
├── docs/
│   ├── plan.md(本書)
│   ├── quality-engineering.md / harness-architecture.md / ci-design.md / security.md
│   └── exercises/NN-*.md                    # 意図的欠陥ごとの「作る → 検出 → 原因 → 修正」記録
└── templates/                               # 最終成果物。poc/company-ai-template の v2
```

`verify.sh --changed` が設計上の要点。PostToolUse は編集ファイルだけ、Stop は変更パッケージだけ、CI は全体。
「同じスクリプト、違う範囲」を 1 本で実現し、PoC テンプレートの「毎回 tsc 全体実行」問題を解く。

## 6. Harness Architecture(調査 4.2 の L0〜L11 を採用)

```
                速度      信頼度   バイパス   役割
CLAUDE.md/rules 即時      低       可        「何を守るか」の宣言。短く。(L1)
Skills          即時      低       可        「どうやるか」の手順。長くてよい。(L2)
Hooks/deny      秒        中       可*       編集直後の fast feedback と危険操作の拒否。(L3)
Sandbox         -         中       可*       FS / network / credential の境界。(L4)
Subagents       分        低〜中   可        意味レベルのレビュー(非決定的)。block にしない。
── ここまでは Agent への「支援」と「境界」。品質保証ではない ──
pre-commit      秒        中       可        漏洩の最終ローカル防衛線。(L5)
CI              分        高       不可**    Repository 全体の決定的検証。(L7)
Rulesets        -         最高     不可      ** CI を「不可」にするのはこれ。(L6)
Policy as Code  秒        高       不可      ガイドラインの実行可能化。(L9)
Human approval  -         -        不可      HITL レベルに応じた承認。(L10)
Nightly         時間      高       不可      重いスキャン、ドリフト検出。
* managed settings で補強可能だが本プロジェクトの範囲外
```

原則:

- CLAUDE.md に手順を書かない。指示で守らせたいことは可能な限り Hook に変換する。
- Hooks は品質ゲートではなく「CI で落ちる時間を前倒しするもの」。
- CI の出力を Agent に戻す経路(`gh run view --log-failed` を使う skill)まで含めて初めてハーネスが閉じる。
- 必須チェックは最小集合。flaky test ひとつで開発が止まる構成にしない。

### HITL レベルと本リポジトリの操作対応

| Level | 内容 | 本リポジトリでの対応 |
|---|---|---|
| HITL-1 | AI + 自動テスト | feature branch での作業 |
| HITL-2 | + セキュリティ検査 | PR の required checks |
| HITL-3 | + 人間承認 | `main` への merge(Rulesets) |
| HITL-4 | + Platform/Security 承認 | `.github/**`, `.claude/**`, `policies/**`, `infra/**`, 依存追加(CODEOWNERS + `/add-dependency`) |
| HITL-5 | 人間のみ | `terraform apply`(deny)、DB 破壊的変更、秘密ローテーション |

## 7. 学習ロードマップ

各 Phase は「概念説明 → 最小実装 → 実行 → 意図的に壊す → 検出確認 → 修正 → docs/exercises に記録」のサイクル。
成熟度モデル(調査 15.2)の推奨順序「3 → 2 → 1」に従い、Phase 0 で Rulesets を先に置く。

| Phase | テーマ | 到達 | 追加するもの | 意図的欠陥 | 防げるようになる欠陥 |
|---|---|---|---|---|---|
| 0 | 土台 + サーバ強制の最小形 | L3 骨格 | monorepo 疎通、Rulesets(required approval、CODEOWNERS)、secret push protection、SHA pin ポリシー、AGENTS.md 最小、baseline 記録 | `main` 直 push | 「CI が無い状態で何が素通りするか」の記録 |
| 1 | 静的ゲート | L2 | Biome / Ruff / basedpyright / tsc、`verify.sh --changed`、PostToolUse hook、CI(path filter) | `any` 乱用、floating promise、型抑制コメント | 存在しない API、型の辻褄合わせ、規約逸脱 |
| 2 | テスト + 完了条件 | L2 | Vitest / pytest、Stop hook = verify、差分カバレッジ報告、lefthook | 失敗テスト、実装をなぞるテスト | リグレッション。「Agent がテストしたと言う」≠「CI が通る」 |
| 3 | 結合・ビルド・境界 | L3 | Testcontainers、docker build、`permissions.deny` / guard hooks、保護パス(Playwright は Phase 7 へ、sandbox は Phase 5 へ) | SQLi、`.env` 読取、`git push --force`、hook 自身のバグ | サービス間不整合、危険操作 |
| 4 | セキュリティ | L3 | Semgrep 自作ルール(taint)+ p/default、Trivy fs、dependency-review、CodeQL / Scorecard(Nightly)、pnpm minimumReleaseAge / trustPolicy、Dependabot cooldown、`/add-dependency` skill(Rego は Phase 5 へ)、enricher の SSRF 対策実装 | 文字列連結 SQL、検証なし SSRF、脆弱依存、ダミー鍵 | 既知の脆弱パターン、既知 CVE、公開直後の悪性版 |
| 5 | Container / IaC / Actions / Policy | L3 | Hadolint、Trivy config / image、actionlint、zizmor、Conftest / Rego(workflows・package.json・Terraform、ルールの unit test 付き)、harden-runner(audit)、Terraform module、checksum 固定の composite action(sandbox は Phase 8 へ) | root Dockerfile、公開 S3、全開 SSH、IAM `*`、`pull_request_target`、SHA 未固定、`^` 依存 | 実行環境の設定不備、CI 乗っ取り、規約の機械検査 |
| 6 | Go 追加 + テンプレート化 | L4 | shortener(distroless)、Go toolchain(gofmt / vet / golangci-lint / `-race` / govulncheck)、`scripts/verify/go.sh`、CI go job、`/new-service` skill(reusable workflow 化は Phase 8 の `templates/` と一緒に) | data race、`go vet` printf、errcheck、gosec、到達可能な脆弱依存 | 3 言語目を何分で乗せられるか(実測は Exercise 07) |
| 7 | テストの信頼性 + フィードバックループ | L5 入口 | Stryker / mutmut(Nightly 週次、報告のみ)、dependency-cruiser / import-linter(error)、knip(warn)、test-reviewer subagent、`/fix-ci` skill、PR 時の SARIF を HIGH+ に限定 | 同語反復テスト、レイヤー違反、未使用依存 | テストの質、構造の腐敗 |
| 7b | アプリ配線 + E2E | - | api → enricher(title 補完)/ shortener(短縮コード)を zod 検証付きクライアントで配線、web のフォーム + 型付き API client、Playwright smoke(API モック、CI)、compose で全サービス結合確認 | サービス間の契約不一致(応答フィールド名の変更) | 結合の劣化(検出は実行時 warn のみ。契約テストは Phase 8 の課題) |
| 8a | 契約 + 出荷物の証明 | L5 | zod → JSON Schema の契約(`contracts/`)+ producer 側契約テスト(Go / Py)、test-reviewer subagent の実行と対応(バグ 1 件発見)、`release.yml`(GHCR、provenance / SBOM attestation、image gate。タグ未実行) | 応答フィールド名の変更 | サービス間契約の破壊、出荷物の出所不明 |
| 8b | 一般化 + 運用 | L4 | `templates/harness`(copier、49 ファイル、生成検証済み)、docs 4 本、`scripts/verify/targets.sh` への固有値の集約、README の復旧手順、`v0.1.0` release(SLSA provenance + CycloneDX SBOM を `gh attestation verify` で確認)、Dependabot BLOCKED の原因特定(Code Owner レビュー = 意図どおり)、sandbox は設計例のみ、harden-runner は audit のまま | copier.yml の YAML、nested Biome config | テンプレートのドリフト |

Phase 1〜4 が本質。ここまでで 7 割の価値が出る。

## 8. 調査レポートとの差分(このプロジェクトで検証すること)

- PoC テンプレートは TS 単一言語。`verify.sh` の多言語化・範囲指定は未検証。
- PoC の自己矛盾を教材化する: `guard-bash.sh` が `curl | sh` を deny するのに `ci.yml` が `curl | sh` でツール導入、Actions の SHA 未固定、`post-edit-check.sh` の tsc 全体実行。
- 調査が再確認を求める事項を実機で確認する: Biome の型情報 lint の範囲、Stop hook の 8 回上限、PostToolUse の block 不可、gitleaks の保守状況。
- 依存追加の全面 deny は 1 人の学習環境では DX コストが高い。仕組みは実装して体験し、常時有効化は Phase 4 で判断。
- Repository は **public**(`nkctkt/learn_harness`、2026-09-05 決定)。個人・組織とも GitHub Free のため、private では Rulesets / required checks 自体が使えず L6 が成立しない。CodeQL / push protection / dependency review も private では GHAS が必要。本物の秘密情報は置かない。
- 単独メンテナのため Rulesets の required approvals は 0。1 にすると全 merge が admin bypass になり、bypass が常態化する方が害が大きい。サーバ強制の実体は required status check(`ci-ok`)。テンプレート向けには approvals ≥ 1 を推奨値として docs に残す。

## 9. 最終成果物

- Application: 動作する Reading Shelf
- Quality Toolchain: TS / Python / Go の標準ツールチェーン(`scripts/verify/*`)
- GitHub Actions: Production に近い CI pipeline
- Claude Code Harness: CLAUDE.md / rules / Skills / Hooks / agents / settings
- Documentation: `docs/quality-engineering.md`, `docs/harness-architecture.md`, `docs/ci-design.md`, `docs/security.md`, `docs/exercises/*`
- Reusable Harness: `templates/`(copier 化)

## 10. 既知のハーネスの穴(発見順に追記)

- PostToolUse hook は `Edit|Write` ツールにしか反応しない。Bash の heredoc でファイルを書くと素通りする(Exercise 01 で発生)。Stop hook の `verify.sh --changed`(Phase 2)が受け止める設計にする。
- Hook は `.claude/settings.json` を編集すれば無効化できる。guard-edit が `.claude/**` への書込を ask にし、CODEOWNERS で承認を必須にしている(Phase 3)。それでも hooks 配列ごと消されれば両方消えるので、最終防衛線は CI と Rulesets。
- **hook の構文エラーは Agent を完全停止させる**(Exercise 04)。bash の構文エラーは exit 2 = block で、guard-bash と guard-edit が同時に壊れると Bash も Edit/Write も使えず、Agent 自身では修復できない。対策: pre-commit の `bash -n`、hook 変更は CODEOWNERS 承認、README に人間向けの復旧手順。
- guard-bash は文字列リテラル内の hook 回避フラグにも反応する(既知の誤検知)。hook のテストケースはファイルに置く。

## 11. 環境メモ(2026-09-05 時点)

- あり: node 24, pnpm 11, uv 0.6, python 3.13, docker 27, terraform 1.14
- なし(Phase 到達時に導入): go, gh, gitleaks, trivy, biome(pnpm 経由)
