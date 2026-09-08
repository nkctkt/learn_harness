#!/usr/bin/env bash
# PreToolUse(Edit|Write|MultiEdit): 「計画が先、コードは後」を決定論的に強制する(AI-DLC の plan-approval guard)。
#
#   active な intent があり、その計画ゲート(Gate plan)が未承認のあいだは、アプリ・サービス・インフラ・契約への
#   書込を deny する。記録(docs/intents/)、docs、ハーネス自体、テスト以外の場所は対象外。
#   active な intent が無ければ何もしない(小さな修正は intent 無しでよい)。
#   HARNESS_REQUIRE_INTENT=1 を settings.json の env で与えると、intent 無しの保護領域書込も deny する(厳格モード)。
#
# 無いと何が起きるか: Agent は先にコードを書き、計画を後から「出力」として書く。AI-DLC の field report と同じ。
# 検出できないもの: Bash の heredoc / sed による書込(guard-bash.sh が同じ条件で ask にする)。
set -uo pipefail
command -v jq >/dev/null 2>&1 || exit 0
on_err() {
  jq -n --arg r "guard-plan-approval.sh 自身がエラーで終了しました。hook を修正してください。" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}
trap on_err ERR
input="$(cat)"
path="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')"
[ -z "$path" ] && exit 0
root="${CLAUDE_PROJECT_DIR:-$(pwd)}"
rel="${path#"$root"/}"
case "$rel" in
  apps/*|services/*|packages/*|infra/*|contracts/*) ;;   # 保護領域
  *) exit 0 ;;
esac
deny() {
  # 判定を記録する(Phase 10、improvement-plan H1)。判定 JSON を出す直前に 1 回だけ。失敗しても判定は変えない。
  "$root/scripts/intent.sh" event HOOK_DENY "guard-plan-approval: ${1:0:80}" >/dev/null 2>&1 || true
  jq -n --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}
[ -x "$root/scripts/intent.sh" ] || exit 0
if dir="$("$root/scripts/intent.sh" active 2>/dev/null)"; then
  gate="$(sed -n 's/^- Gate plan: //p' "$dir/state.md" | head -n1)"
  case "$gate" in
    approved*) exit 0 ;;
    *) deny "計画が未承認です(intent $(basename "$dir")、Gate plan: ${gate:-pending})。${rel} を書く前に /plan-units で plan.md を書き、gate present plan → 人間の承認 → gate approve plan → stage construction の順に進めてください。計画を後から書くことは禁止です。" ;;
  esac
elif [ "${HARNESS_REQUIRE_INTENT:-0}" = 1 ]; then
  deny "active な intent がありません(HARNESS_REQUIRE_INTENT=1)。${rel} を変更する前に /intent で記録を作ってください。"
fi
exit 0
