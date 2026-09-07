# templates/harness — ハーネスの copier テンプレート

`learn_harness` で構築・検証したハーネス(検証スクリプト、Claude Code の hooks / skills / agents、GitHub Actions、Rulesets、Rego / Semgrep ポリシー、lefthook)を、新しいリポジトリに敷くためのテンプレート。
アプリケーションコードは含まない。**「最初から正しい状態」で始めるための L0(Golden Path)**。

## 適用

```
# 新規リポジトリ(空でよい)で
uv tool run copier copy --trust gh:nkctkt/learn_harness --subdirectory templates/harness .
#   ローカルのクローンから: uv tool run copier copy --trust /path/to/learn_harness/templates/harness .

# 後からテンプレートの更新を取り込む(3-way merge)
uv tool run copier update --trust
```

質問されるもの: プロジェクト名、GitHub オーナー、言語(ts / py / go の複数選択)、各言語のパッケージパス、Dockerfile、Terraform ディレクトリ、必要承認数。
生成される `scripts/verify/targets.sh` がプロジェクト固有の値を持ち、他の verify スクリプトは `learn_harness` のものがそのまま入る。

## 生成されるもの

| パス | 役割 | 層 |
|---|---|---|
| `AGENTS.md`(TODO 付き)、`CLAUDE.md` | 指示。200 行以内に保つ | L1 |
| `.claude/skills/{add-dependency,new-service,fix-ci}` | 手順 | L2 |
| `.claude/agents/test-reviewer.md` | テストの弱さを読む subagent | 助言 |
| `.claude/settings.json`、`.claude/hooks/*.sh` | deny、guard-bash / guard-edit / guard-secrets(PreToolUse)、post-edit-check(PostToolUse)、stop-verify(Stop) | L3 |
| `.claude/sandbox.disabled.json` | sandbox の設計例(有効化は宛先を洗い出してから) | L4 |
| `lefthook.yml`、`.gitleaks.toml` | pre-commit(staged verify、gitleaks、shell 構文、Conventional Commits) | L5 |
| `.github/rulesets/main-protection.json`、`scripts/github/apply-rulesets.sh` | Rulesets as code(PR 必須、`ci-ok` + `security-ok`、Code Owner レビュー、会話解決) | L6 |
| `.github/workflows/{ci,security,nightly,release}.yml`、`.github/actions/setup-infra-tools` | CI(全 action SHA 固定、harden-runner、gate / report 分離) | L7 |
| `policies/rego/*`、`policies/semgrep/*` | 組織ルール(SHA 固定、完全固定、公開 SG 禁止 …)と自作 SAST ルール(unit test 付き) | L9 |
| `.github/CODEOWNERS`、`.github/dependabot.yml` | 人間承認の対象、cooldown 7 日 | L10 |
| `scripts/verify.sh`、`scripts/verify/*.sh` | 全層が呼ぶ 1 本の検証(`--files` / `--changed` / 全体、`--only`) | 共通 |
| `biome.json`、`eslint.config.mjs`、`knip.json`、`.dependency-cruiser.cjs`、`.trivyignore` | ツール設定 | - |

## 適用後に人間がやること(順番どおり)

1. **`AGENTS.md` の TODO を埋める**(構成、コマンド)。長くしない。
2. **`.github/workflows/ci.yml` を対象に合わせる**: `changes` の path filter、言語 job の有無(使わない言語の job は削除)、docker matrix、`ci-ok` の `needs`。`security.yml` の `infra` job はそのままでよい。
3. **ツール設定を対象に合わせる**: `biome.json` / `eslint.config.mjs` / `knip.json` / `.dependency-cruiser.cjs`(TS)、各 Python プロジェクトの `pyproject.toml`(Ruff / basedpyright / pytest / import-linter の設定は `learn_harness/services/enricher/pyproject.toml` を参照)、各 Go モジュールの `.golangci.yml`(`learn_harness/services/shortener/.golangci.yml`)。
4. **Semgrep の自作ルール**は `learn_harness` 固有(Drizzle、Hono、FastAPI)。使わないものは削除し、自分のフレームワーク向けに書き直す。`semgrep --test policies/semgrep` を通す。
5. **Rego の `package_json.rego` / `terraform.rego`** は汎用。`github_workflow.rego` も汎用。
6. **GitHub**: `gh repo create` → push → `scripts/github/apply-rulesets.sh` → Settings で secret scanning と push protection を有効化(private では GHAS が要る)。Free プランの private リポジトリでは Rulesets 自体が使えない。
7. **ローカルツール**: `brew install gitleaks semgrep trivy hadolint actionlint conftest`(+ `go golangci-lint`、`go install golang.org/x/vuln/cmd/govulncheck@latest`)。zizmor は `uv tool run zizmor`。
8. **pnpm**: root の `package.json` に `"prepare": "lefthook install"`、`pnpm-workspace.yaml` に `saveExact` / `minimumReleaseAge: 10080` / `trustPolicy: no-downgrade` / `blockExoticSubdeps` / `allowBuilds`(`learn_harness/pnpm-workspace.yaml` を参照)。
9. **Actions の SHA を更新する**: テンプレートの SHA は 2026-09 時点。Dependabot(actions)が週次で更新 PR を出す。bot PR は Code Owner の approve が要る。
10. **release.yml** は `v*` タグで GHCR に push する。不要なら削除。使うなら最初のタグで `gh attestation verify` まで確認する。
11. **最初の PR で意図的に壊す**: 型エラー、`any`、ダミー鍵、`^` 付き依存を入れて、hook → pre-commit → CI の順に止まることを確認してから本番のコードを書き始める(`learn_harness/docs/exercises/01`〜)。

## 復旧手順(hook が全滅した時)

`learn_harness/README.md` の「ハーネスが自分を止めた時の復旧手順」を参照。要点: `bash -n .claude/hooks/*.sh` で壊れた hook を特定し、`git restore` で戻す。

## このテンプレートに入れなかったもの

- アプリの雛形(言語ごとの `apps/` / `services/`)。ハーネスとアプリは寿命が違う。
- Claude sandbox の有効化。宛先の洗い出し後に `.claude/sandbox.disabled.json` を `settings.json` に取り込む。
- managed settings / plugin marketplace による組織強制(調査 5.5)。個人リポジトリの範囲外。
- 全サービス E2E の CI 化。契約テスト(`learn_harness/contracts/`、Exercise 10)の方が安い。
