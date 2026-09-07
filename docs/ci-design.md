# CI Design — Job 構成、並列化、キャッシュ、Required checks、Merge policy

GitHub Actions を「Agent を信用せずに Repository の品質を保証する場所」として設計した記録。

## 1. Workflow の分割と責務

| Workflow | トリガー | 責務 | required check |
|---|---|---|---|
| `ci.yml` | PR、main push | 言語ゲート(ts / py / go)、e2e(web)、docker build + image scan、gitleaks 全履歴 | `ci-ok` |
| `security.yml` | PR、main push | Semgrep、Trivy fs、dependency review、infra(hadolint / actionlint / zizmor / terraform / trivy config / conftest) | `security-ok` |
| `nightly.yml` | 毎日 03:00 JST、手動 | CodeQL(3 言語)、Trivy ドリフト、Scorecard、mutation(日曜) | なし(Security タブ・summary) |
| `release.yml` | `v*` タグ、手動 | GHCR push、provenance / SBOM attestation、image gate | なし |

分割の基準: **required check の粒度**(`ci-ok` / `security-ok` の 2 つ)と **権限**(release だけが `packages` / `id-token` / `attestations` の write を持つ)。

## 2. Job 構成(ci.yml)

```
changes(paths-filter)
 ├─ ts     (apps/** packages/** → biome, tsc, eslint, vitest+coverage, contracts:check, depcruise, knip)
 ├─ py     (services/**        → ruff, basedpyright, pytest+cov, import-linter)
 ├─ go     (services/shortener → gofmt, vet, golangci-lint, test -race, govulncheck)
 ├─ e2e    (apps/web           → playwright, mocked api)
 ├─ docker (Dockerfile 等      → matrix 4 image: buildx(GHA cache) → trivy image)
 ├─ secrets(常時               → gitleaks 全履歴)
 └─ ci-ok  (always, needs 全部 → failure / cancelled が 1 つでもあれば fail)
```

- **path filter で skip された job は required check では成功扱い**。ただし言語 job を直接 required に登録すると「走らなかった PR」が pending のまま止まるので、集約 job `ci-ok` だけを登録する。
- 言語 job は **`scripts/verify.sh --only <stage>`** を呼ぶだけ。CI 固有のロジックを workflow に書かない(「ローカルと同じ」を構造で保証する)。
- docker job は matrix で 4 image を並列にビルドし、そのままビルド済み image を Trivy にかける。

## 3. 並列化とキャッシュ

| 対象 | 方法 | 効果 |
|---|---|---|
| 言語 job | 独立 job として並列 | 最長 job(ts: 約 45 秒)が全体時間 |
| pnpm | `actions/setup-node` の `cache: pnpm` | install 数秒 |
| uv | `setup-uv` の `enable-cache` + `cache-dependency-glob` | 同上 |
| Go | `setup-go` の `cache-dependency-path: go.sum` | 同上 |
| Docker | `cache-from/to: type=gha,scope=<image>` | 2 回目以降 30〜60 秒 |
| Terraform provider | `.terraform` を verify.sh 内で再利用(CI では毎回 init、30 秒) | - |
| Trivy DB | action がキャッシュ | - |

PR 1 回の壁時計は約 2〜3 分(docker と e2e が律速)。

## 4. Required checks と Merge policy(Rulesets)

`.github/rulesets/main-protection.json`(`scripts/github/apply-rulesets.sh` で適用):

| ルール | 設定 | 理由 |
|---|---|---|
| PR 必須 | on | 直接 push は GH013 で拒否(Ex.00) |
| required status checks | `ci-ok`、`security-ok`(strict: false) | 集約 job のみ。strict にすると main が進むたびに再実行が要る |
| approvals | 0(テンプレートでは 1 推奨) | 単独メンテナ。1 にすると全 merge が admin bypass になり bypass が常態化する |
| Code Owner レビュー | on | ハーネス自体と bot PR に人間を挟む(HITL-4)。owner 自身の PR は免除される |
| 会話の解決 | on | code scanning のコメントも対象になる → PR 時 SARIF は HIGH 以上に限定(Ex.07) |
| 線形履歴 / 削除禁止 / force push 禁止 | on | - |
| merge 方法 | merge / squash | このプロジェクトは粒度の細かい履歴を残すため merge commit |
| bypass | Repository admin、PR 経由のみ | bypass を可視化・監査可能に |

## 5. Actions のセキュリティ

| 対策 | 実装 | 検証 |
|---|---|---|
| SHA 固定 | 全 `uses:` を 40 桁 SHA + `# vN` コメント | Rego(`github_workflow.rego`)、zizmor、Dependabot(actions) |
| 最小権限 | トップレベル `permissions: contents: read`、必要な job だけ追加 | Rego(未宣言 / write-all を拒否) |
| credential 残留 | 全 checkout に `persist-credentials: false` | zizmor `artipacked` |
| script injection | 式は `env:` 経由、`run:` に `${{ }}` を直接書かない | actionlint、zizmor、Rego |
| `pull_request_target` 禁止 | 使わない | Rego、zizmor |
| egress 監視 | harden-runner `egress-policy: audit`(block は宛先確定後) | StepSecurity の insights |
| ツール導入 | composite action で sha256 検証(hadolint / actionlint / conftest) | - |
| バージョン一致 | trivy `version:`、golangci-lint `version:`、shellcheck はローカル更新 | CI と local のズレで 2 回落ちた(Ex.05, 06) |

## 6. Gate と Report の分離

| ツール | Gate(merge を止める) | Report(見えるようにする) |
|---|---|---|
| Trivy fs | table、HIGH 以上、`--ignore-unfixed`、exit 1 | SARIF、HIGH 以上(PR)/ 全 severity(Nightly) |
| Trivy image | table、HIGH 以上(docker job / release) | - |
| Semgrep | `--error`(ERROR 以上) | SARIF |
| coverage | なし | job summary |
| mutation | なし | job summary(週次) |
| knip | なし | verify の出力(`!`) |
| CodeQL / Scorecard | なし | Security タブ |

同じツールでも「狭く確実に止める」設定と「広く見せる」設定は別に持つ。trivy-action は SARIF 出力時に全 severity で exit-code を効かせる(Ex.05)ので、1 ステップで両立しない。

## 7. Bot PR(Dependabot)の扱い

- 週次、cooldown 7 日(major 30 日)、grouping(dev-tooling / runtime-minor / actions / python-minor)。
- bot PR は Code Owner レビュー必須により owner の approve が要る。**auto-merge はしない**(ハーネス自体を bot が変える PR に人間を挟む)。
- triage の順序: (1) actions の SHA 更新(Rego と CI が通っていれば低リスク)→ (2) minor / patch のグループ → (3) docker base の major(Ex.06 の image CVE と、ランタイム互換性を確認してから)。
- Dependabot は上位版が出ると PR を作り直すので、番号ではなく `gh pr list --author app/dependabot` で追う。

## 8. CI から Agent への還流

- 失敗時: `gh run view --job <id> --log` → `✘ <step>` の直後に原因。手順は `/fix-ci` skill。
- job summary: coverage(ts / py)、mutation score(週次)、release の検証コマンド。
- SARIF → Security タブ(Semgrep / Trivy / CodeQL / Scorecard)。PR コメントになるのは HIGH 以上だけ。

## 9. 計測(2026-09-07 時点、PR 1 回)

| job | 時間 |
|---|---|
| detect changes | 5〜15 秒 |
| ts | 35〜50 秒 |
| py | 10〜30 秒 |
| go | 約 40 秒 |
| e2e | 約 1 分 |
| docker(各) | 35 秒〜1 分 40 秒 |
| semgrep | 約 40 秒 |
| trivy fs | 約 30 秒 |
| infra | 約 30 秒 |
| 合計(壁時計) | 2〜3 分 |
