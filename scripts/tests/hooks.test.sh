#!/usr/bin/env bash
# Phase 9 で追加した hook の振る舞いテスト。hook に JSON を流し込み、決定(deny / ask / allow)と副作用を検証する。
# 記録は一時ディレクトリ(INTENTS_DIR)に作るので、リポジトリの docs/intents/ は触らない。
# hook のテストケースをファイルに置く理由: guard-bash は Bash 文字列全体を見るので、対話で書くと誤検知する(plan §10)。
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -r "$TMP"' EXIT     # allow-secret: 一時ディレクトリの後始末
export INTENTS_DIR="$TMP/intents" CLAUDE_PROJECT_DIR="$ROOT"; mkdir -p "$INTENTS_DIR"
H="$ROOT/.claude/hooks"; I="$ROOT/scripts/intent.sh"
fail=0; n=0
ok() { n=$((n+1)); echo "  ✔ $1"; }
ng() { n=$((n+1)); fail=1; echo "  ✘ $1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/      /'; }
# decision <hook> <json> → deny|ask|allow(出力無し)|block(exit 2)
decision() {
  local out rc; out="$(printf '%s' "$2" | "$H/$1" 2>/dev/null)"; rc=$?
  [ $rc -eq 2 ] && { echo block; return; }
  [ -z "$out" ] && { echo allow; return; }
  printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "allow"' 2>/dev/null || echo allow
}
expect() { local want="$1" name="$2" hook="$3" json="$4" got; got="$(decision "$hook" "$json")"; [ "$got" = "$want" ] && ok "$name → $want" || ng "$name (want $want, got $got)"; }
edit_json() { printf '{"tool_name":"Write","tool_input":{"file_path":"%s/%s","content":"x"}}' "$ROOT" "$1"; }
bash_json() { printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$1"; }

echo "[hooks.test]"
command -v jq >/dev/null || { echo "  - jq が無いので skip"; exit 0; }
for f in "$H"/*.sh; do bash -n "$f" && ok "bash -n ${f##*/}" || ng "syntax ${f##*/}"; done
jq -e '.hooks.SessionStart and .hooks.UserPromptSubmit and (.hooks.PostToolUse | map(.matcher) | index("AskUserQuestion"))' "$ROOT/.claude/settings.json" >/dev/null \
  && ok "settings.json に SessionStart / UserPromptSubmit / AskUserQuestion が配線されている" || ng "settings.json の配線"

# --- intent が無い時は何もしない(小さな修正は intent 不要)------------------------------------------------
expect allow "intent 無し: apps への Write" guard-plan-approval.sh "$(edit_json apps/api/src/x.ts)"
got="$(printf '%s' "$(edit_json apps/api/src/x.ts)" | HARNESS_REQUIRE_INTENT=1 "$H/guard-plan-approval.sh" | jq -r '.hookSpecificOutput.permissionDecision')"
[ "$got" = deny ] && ok "厳格モード(HARNESS_REQUIRE_INTENT=1)では intent 無しの apps 書込を deny" || ng "厳格モード (got $got)"

# --- 計画未承認のあいだは保護領域を書けない ---------------------------------------------------------------
"$I" new demo --scope feature >/dev/null
expect deny  "計画未承認: apps への Write" guard-plan-approval.sh "$(edit_json apps/api/src/x.ts)"
expect deny  "計画未承認: services への Write" guard-plan-approval.sh "$(edit_json services/enricher/x.py)"
expect deny  "計画未承認: infra への Write" guard-plan-approval.sh "$(edit_json infra/terraform/x.tf)"
expect allow "計画未承認: docs/intents への Write は許可(計画を書くため)" guard-plan-approval.sh "$(edit_json docs/intents/x/plan.md)"
expect allow "計画未承認: docs への Write は許可" guard-plan-approval.sh "$(edit_json docs/adr/0001-x.md)"
expect allow "計画未承認: .claude への Write は許可(guard-edit が ask にする)" guard-plan-approval.sh "$(edit_json .claude/skills/x/SKILL.md)"
expect deny  "計画未承認: Bash リダイレクトで apps に書く" guard-bash.sh "$(bash_json 'echo x > apps/api/src/y.ts')"
expect allow "計画未承認: Bash で apps を読むだけ" guard-bash.sh "$(bash_json 'cat apps/api/src/y.ts')"
expect allow "計画未承認: Bash で docs に書く" guard-bash.sh "$(bash_json 'echo x > docs/notes.md')"

# --- 受領証・状態・監査ログは正規の入口以外から触れない -----------------------------------------------------
D="$("$I" active)"; REL="docs/intents/$(basename "$D")"
expect deny "guard-edit: state.md への Write" guard-edit.sh "$(edit_json "$REL/state.md")"
expect deny "guard-edit: audit.log への Write" guard-edit.sh "$(edit_json "$REL/audit.log")"
expect allow "guard-edit: intent.md への Write は許可" guard-edit.sh "$(edit_json "$REL/intent.md")"
expect ask  "guard-bash: audit.log への追記" guard-bash.sh "$(bash_json "echo x >> $REL/audit.log")"
expect ask  "guard-bash: Agent 自身による human-turn" guard-bash.sh "$(bash_json 'scripts/intent.sh human-turn me')"
expect allow "guard-bash: gate present は正規の入口" guard-bash.sh "$(bash_json 'scripts/intent.sh gate present intent')"
expect allow "guard-bash: status は正規の入口" guard-bash.sh "$(bash_json 'scripts/intent.sh status')"

# --- 人間の在席の記録と、それによる承認 ----------------------------------------------------------------------
"$I" gate present intent >/dev/null
"$I" gate approve intent >/dev/null 2>&1 && ng "HUMAN_TURN 無しで承認できてしまった" || ok "HUMAN_TURN 無しの承認は拒否"
printf '{"hook_event_name":"UserPromptSubmit","prompt":"approve"}' | "$H/record-human-turn.sh"
grep -q '	HUMAN_TURN	UserPromptSubmit$' "$D/audit.log" && ok "UserPromptSubmit で HUMAN_TURN が記録される" || ng "HUMAN_TURN が無い" "$(cat "$D/audit.log")"
"$I" gate approve intent >/dev/null && ok "人間の応答後は承認できる" || ng "承認できない"
printf '{"hook_event_name":"PostToolUse","tool_name":"AskUserQuestion","tool_response":{}}' | "$H/record-human-turn.sh"
grep -q '	HUMAN_TURN	PostToolUse:AskUserQuestion$' "$D/audit.log" && ok "AskUserQuestion の応答でも HUMAN_TURN が記録される" || ng "AskUserQuestion の HUMAN_TURN が無い"

# --- 計画承認後は保護領域を書ける -----------------------------------------------------------------------------
"$I" stage inception >/dev/null
printf '# plan\n\n## 分解\n\n```yaml\nunits:\n  - name: u1-a\n    depends_on: []\n```\n\n## 順序と walking skeleton\n\n## Definition of Done\n' > "$D/plan.md"
"$I" gate present plan >/dev/null; printf '{"hook_event_name":"UserPromptSubmit"}' | "$H/record-human-turn.sh"; "$I" gate approve plan >/dev/null
expect allow "計画承認後: apps への Write" guard-plan-approval.sh "$(edit_json apps/api/src/x.ts)"
expect allow "計画承認後: Bash リダイレクトで apps に書く" guard-bash.sh "$(bash_json 'echo x > apps/api/src/y.ts')"

# --- SessionStart は状態を注入する ---------------------------------------------------------------------------
ctx="$(printf '{"hook_event_name":"SessionStart","source":"startup"}' | "$H/session-start.sh" | jq -r '.hookSpecificOutput.additionalContext')"
printf '%s' "$ctx" | grep -q 'intent: .*demo' && ok "SessionStart が active intent を注入する" || ng "SessionStart の文脈" "$ctx"
printf '%s' "$ctx" | grep -q 'stage=inception' && ok "SessionStart が stage を注入する" || ng "stage が無い" "$ctx"

echo "  $n assertions, fail=$fail"
exit $fail
