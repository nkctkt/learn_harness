#!/usr/bin/env bash
# セキュリティ段: Semgrep(SAST、自作ルール + 汎用)と Trivy(SCA / secret / misconfig)。
# 責務: Semgrep はソースのパターン、Trivy は lockfile と設定ファイル。どちらもコードの意図は見ない。
# 全体モードでのみ実行(数秒〜数十秒)。--files / --changed では skip する(Hook 層には重い)。
set -uo pipefail
source "$(dirname "$0")/_lib.sh"
cd "$VERIFY_ROOT"
echo "[sec]"
if [ "${VERIFY_MODE}" != all ]; then echo "  - skipped (full mode only)"; exit 0; fi

if command -v semgrep >/dev/null 2>&1; then
  step "semgrep --test policies/semgrep (ルール自体のテスト)" semgrep --test policies/semgrep --metrics=off
  # ルール検体(policies/semgrep/*.ts|py)は意図的に悪いコードなのでスキャン対象から外す(--test でのみ使う)
  step "semgrep scan (自作ルール + p/default)" semgrep scan --config policies/semgrep --config p/default \
    --exclude 'policies/semgrep/*.ts' --exclude 'policies/semgrep/*.py' --metrics=off --error --quiet .
else
  echo "  - semgrep not installed (CI で実行される)"
fi

if command -v trivy >/dev/null 2>&1; then
  # lockfile の既知 CVE(HIGH 以上)、秘密情報、設定不備。修正版が無いものは除外(--ignore-unfixed)。
  step "trivy fs (vuln HIGH+, secret, misconfig)" trivy fs --scanners vuln,secret,misconfig \
    --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 --quiet --skip-dirs node_modules,.venv .
else
  echo "  - trivy not installed (CI で実行される)"
fi
exit $STEP_FAILED
