#!/usr/bin/env bash
# docs 段: ライフサイクルの記録(docs/intents)とハーネス自身の振る舞いテスト。
# 責務:
#   intent.sh check         … 承認の受領証(提示 → 人間の応答 → 承認)、state と audit の一致、必須節、unit DAG の循環
#   scripts/tests/*.test.sh … intent.sh と hook の振る舞いテスト(全体モードのみ。一時ディレクトリで動く)
# --files / --changed では、記録・スクリプト・hook に触れた時だけ check を走らせる(数十 ms)。
set -uo pipefail
source "$(dirname "$0")/_lib.sh"
cd "$VERIFY_ROOT"
echo "[docs]"
if [ "$VERIFY_MODE" != all ]; then
  hit="$(filter_files '^(docs/intents/|scripts/intent\.sh|scripts/tests/|\.claude/hooks/)' "$@")"
  [ -z "$hit" ] && { echo "  - skipped (no intent / hook changes)"; exit 0; }
fi
step "intent.sh check (records: receipts, state/audit, sections, DAG)" scripts/intent.sh check
if [ "$VERIFY_MODE" = all ]; then
  for t in scripts/tests/*.test.sh; do step "$(basename "$t")" "$t"; done
fi
exit $STEP_FAILED
