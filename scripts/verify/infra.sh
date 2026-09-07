#!/usr/bin/env bash
# インフラ段: Dockerfile / Terraform / GitHub Actions / ポリシー。全体モードでのみ実行する。
# 責務:
#   hadolint / actionlint  … 構文とベストプラクティス(lint)
#   trivy config           … 汎用の危険設定(misconfig DB)
#   conftest (Rego)        … 組織固有のルール(SHA 固定、完全固定、公開 SG 禁止 等)。ルール自体のテストも回す
#   zizmor                 … ワークフロー固有のセキュリティ(injection、credential 残留、権限)
#   terraform fmt/validate … 整形と型・参照の整合(apply はしない)
set -uo pipefail
source "$(dirname "$0")/_lib.sh"
cd "$VERIFY_ROOT"
unset VIRTUAL_ENV
echo "[infra]"
if [ "${VERIFY_MODE}" != all ]; then echo "  - skipped (full mode only)"; exit 0; fi

DOCKERFILES=(apps/api/Dockerfile apps/web/Dockerfile services/enricher/Dockerfile)
have() { command -v "$1" >/dev/null 2>&1; }
missing() { echo "  - $1 not installed (CI で実行される。brew install $1)"; }

if have hadolint; then step "hadolint (Dockerfiles)" hadolint "${DOCKERFILES[@]}"; else missing hadolint; fi
if have actionlint; then step "actionlint (.github/workflows)" actionlint; else missing actionlint; fi
if have uv; then step "zizmor (workflow security)" uv tool run --quiet zizmor --no-progress --persona regular --min-severity medium .github/workflows; else missing uv; fi

if have terraform; then
  step "terraform fmt -check" terraform -chdir=infra/terraform fmt -check -recursive
  [ -d infra/terraform/.terraform ] || step "terraform init (providers)" terraform -chdir=infra/terraform init -backend=false -input=false -no-color
  step "terraform validate" terraform -chdir=infra/terraform validate -no-color
else missing terraform; fi

if have trivy; then
  # trivy config は単一ターゲットしか受けないので repo 全体を渡す(Dockerfile / Terraform / compose を自動検出)
  step "trivy config (repo, HIGH+)" trivy config --quiet --severity HIGH,CRITICAL --exit-code 1 --skip-dirs node_modules,.venv,.terraform .
else missing trivy; fi

if have conftest; then
  step "conftest verify (Rego ルール自体のテスト)" conftest verify --policy policies/rego
  step "conftest: workflows" conftest test --policy policies/rego --namespace github_workflow .github/workflows/*.yml
  step "conftest: package.json (完全固定)" conftest test --policy policies/rego --namespace package_json package.json apps/api/package.json apps/web/package.json
  step "conftest: terraform" conftest test --policy policies/rego --namespace terraform --parser hcl2 infra/terraform/main.tf infra/terraform/versions.tf
else missing conftest; fi
exit $STEP_FAILED
