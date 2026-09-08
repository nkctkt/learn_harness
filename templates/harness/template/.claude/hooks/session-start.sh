#!/usr/bin/env bash
# SessionStart: セッション開始・再開・compaction 後に、Agent が「今どこにいるか」を再注入する。
#
#   1. active な intent の状態(stage / gates / units / 直近の監査イベント / 次にやること)
#   2. hook 自身の健全性(bash -n)。壊れた hook は exit 2 = 全ツール block になる(Exercise 04)ので、最初に知らせる
#
# 会話の文脈はセッションを跨ぐと消える。状態を Git 管理のファイルに置き、開始時に読み直すのが AI-DLC の
# aidlc-session-start の考え方。ここは「読む」だけで何も書かない。常に exit 0。
set -uo pipefail
root="${CLAUDE_PROJECT_DIR:-$(pwd)}"
command -v jq >/dev/null 2>&1 || exit 0
ctx=""
broken=""
for f in "$root"/.claude/hooks/*.sh; do bash -n "$f" 2>/dev/null || broken="$broken ${f##*/}"; done
[ -n "$broken" ] && ctx="⚠ 構文エラーの hook:$broken(README の復旧手順)。"$'\n'
if [ -x "$root/scripts/intent.sh" ]; then
  st="$("$root/scripts/intent.sh" status 2>&1 || true)"
  ctx="$ctx[intent]"$'\n'"$st"$'\n'
  if printf '%s' "$st" | grep -q '^intent:'; then
    ctx="$ctx"'ルール: ゲートを提示したらターンを終えて人間を待つ。計画(gate plan)承認前に apps/ services/ infra/ を書かない。記録は scripts/intent.sh 経由でのみ更新する。手順は /intent /plan-units /build-unit /create-pr /release /incident /retro。'
  else
    ctx="$ctx"'アプリの振る舞いを変える作業を始める時は /intent で記録を作る(小さな修正は不要)。'
  fi
fi
jq -n --arg c "$ctx" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$c}}'
exit 0
