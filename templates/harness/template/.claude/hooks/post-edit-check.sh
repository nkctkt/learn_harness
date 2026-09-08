#!/usr/bin/env bash
# PostToolUse(Edit|Write): 編集直後に、そのファイルだけを対象に format(自動修正)→ lint → 型検査。
# PostToolUse は block できない(既に書き込み済み)。結果を additionalContext で返し、Agent に修正させる。
# 目的は品質保証ではなく「CI で落ちるまでの時間を数分から数秒に縮める」こと。
set -uo pipefail
input="$(cat)"
path="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')"
[ -z "$path" ] && exit 0
root="${CLAUDE_PROJECT_DIR:-$(pwd)}"
case "$path" in
  *.ts|*.tsx|*.js|*.jsx|*.json|*.jsonc|*.css|*.py|*.go) ;;
  *) exit 0 ;;
esac
out="$("$root/scripts/verify.sh" --fix --files "$path" 2>&1)"
status=$?
if [ $status -ne 0 ]; then
  # 失敗を記録する(Phase 10、improvement-plan H1)。失敗しても出力は変えない。
  "$root/scripts/intent.sh" event POST_EDIT_FAIL "${path#"$root"/}" >/dev/null 2>&1 || true
  jq -n --arg m "$out" '{
    hookSpecificOutput: {
      hookEventName: "PostToolUse",
      additionalContext: ("編集後チェック(scripts/verify.sh --fix --files)で問題が見つかりました。次の作業の前に修正してください。抑制コメントで黙らせないこと。\n" + $m)
    }
  }'
fi
exit 0
