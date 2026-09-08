#!/usr/bin/env bash
# UserPromptSubmit / PostToolUse(AskUserQuestion): 「人間がこのターンに居た」ことを監査ログに記録する(HUMAN_TURN)。
#
# これは承認ゲートの受領証。scripts/intent.sh gate approve は、ゲート提示(GATE_PRESENTED)より後に
# HUMAN_TURN が無ければ承認を拒否する。Agent は human-turn を自分では呼ばない(呼べば捏造だが、
# ローカル層なので防げない。CI の intent.sh check と PR レビューで露見させる)。
#
# なぜ hook が書くのか: 人間の入力を受け取るのは Claude Code 本体だけで、Agent の推論はそれを観測できない。
# 「人間が答えた」という事実を Agent の主張ではなく、ハーネスの事実にする(AI-DLC の aidlc-record-human-turn)。
# 常に exit 0。人間の入力を止める理由は無い。active な intent が無ければ intent.sh 側で何もしない。
set -uo pipefail
root="${CLAUDE_PROJECT_DIR:-$(pwd)}"
[ -x "$root/scripts/intent.sh" ] || exit 0
input="$(cat)"
src="prompt"
if command -v jq >/dev/null 2>&1; then
  src="$(printf '%s' "$input" | jq -r '.hook_event_name // "prompt"' 2>/dev/null || echo prompt)"
  tool="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null || true)"
  [ -n "$tool" ] && src="$src:$tool"
fi
"$root/scripts/intent.sh" human-turn "$src" >/dev/null 2>&1 || true
exit 0
