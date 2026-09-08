#!/usr/bin/env bash
# PreToolUse(Bash): 破壊的・回避的な操作を決定論的に拒否する(Boundaries 層)。
# permissions.deny と二重化している。理由: deny ルールは設定ファイルの編集で緩められるが、hook は別ファイルで残る。
# 「判断」はしない。パターンに一致したら止めるだけ。誤検知は文言を見て人間が対処する。
set -uo pipefail
command -v jq >/dev/null 2>&1 || exit 0
# hook 自身の実行時エラーで決定を返せない時に allow(fail-open)にならないよう、ERR で deny を返す。
# 構文エラーは trap 以前に exit 2 になり全ツールを block する(Exercise 04)。編集後は必ず bash -n を通すこと。
on_err() {
  jq -n --arg r "guard-bash.sh 自身がエラーで終了しました。hook を修正してください。" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}
trap on_err ERR
input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')"
[ -z "$cmd" ] && exit 0

# 判定を記録する(Phase 10、improvement-plan H1)。判定 JSON を出す直前に 1 回だけ呼ぶ。失敗しても判定は変えない。
record() { "${CLAUDE_PROJECT_DIR:-.}/scripts/intent.sh" event "$1" "guard-bash: ${2:0:80}" >/dev/null 2>&1 || true; }
deny() {
  record HOOK_DENY "$1"
  jq -n --arg reason "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$reason}}'
  exit 0
}
ask() {
  record HOOK_ASK "$1"
  jq -n --arg reason "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:$reason}}'
  exit 0
}

# 1) 履歴・作業ツリーを破壊する git 操作(HITL-5: 人間のみ)
if printf '%s' "$cmd" | grep -Eq '(^|[;&|[:space:]])git[[:space:]]+([^;&|]*[[:space:]])?(push[^;&|]*[[:space:]](-f|--force)([[:space:]]|$)|push[^;&|]*[[:space:]]--force-with-lease|reset[[:space:]]+--hard|clean[[:space:]]+-[a-z]*f|branch[[:space:]]+-D[[:space:]]+main|checkout[[:space:]]+--[[:space:]]+\.)'; then
  deny "破壊的な git 操作は禁止です(AGENTS.md)。必要なら理由を添えて人間に依頼してください: $cmd"
fi
# 2) ファイルシステムの破壊
if printf '%s' "$cmd" | grep -Eq '(^|[;&|[:space:]])(rm[[:space:]]+(-[a-zA-Z]*r[a-zA-Z]*f|-[a-zA-Z]*f[a-zA-Z]*r)[[:space:]]|sudo[[:space:]]|mkfs|dd[[:space:]]+if=)'; then
  deny "再帰的削除・特権操作は禁止です: $cmd"
fi
# 3) 本番相当の変更(HITL-5)
if printf '%s' "$cmd" | grep -Eq '(^|[;&|[:space:]])terraform[[:space:]]+(apply|destroy)|(^|[;&|[:space:]])(psql|drizzle-kit)[^;&|]*(DROP[[:space:]]+(TABLE|DATABASE)|drop)'; then
  deny "terraform apply/destroy と DROP は Agent からは実行できません(HITL-5)。plan / generate までにしてください。"
fi
# 4) 検証の回避
if printf '%s' "$cmd" | grep -Eq -- '--no-verify|LEFTHOOK=0|LEFTHOOK_EXCLUDE|SKIP_HOOKS|--no-gpg-sign.*--no-verify'; then
  deny "git hooks の回避(--no-verify / LEFTHOOK=0)は禁止です。失敗の根本原因を直してください。"
fi
# 5) パイプ経由のリモートスクリプト実行
if printf '%s' "$cmd" | grep -Eq '(curl|wget)[^|]*\|[[:space:]]*(sudo[[:space:]]+)?(ba|z)?sh'; then
  deny "リモートスクリプトのパイプ実行は禁止です。パッケージマネージャ経由で導入してください。"
fi
# 6) intent の状態・監査ログ・受領証の直接操作(Phase 9)。scripts/intent.sh の正規の入口以外は ask。
#    human-turn / event は hook 専用(Agent が呼べば承認・判定の捏造)。state.md / audit.log への書込も同様。
if printf '%s' "$cmd" | grep -Eq 'intent\.sh[[:space:]]+(human-turn|event)|docs/intents/[^[:space:]]*/(state\.md|audit\.log)' && printf '%s' "$cmd" | grep -Eq '(human-turn|intent\.sh[[:space:]]+event|>|>>|sed[[:space:]]+-i|tee[[:space:]]|mv[[:space:]]|rm[[:space:]]|cp[[:space:]])'; then
  ask "intent の受領証・状態・監査ログを直接操作しようとしています。承認は人間の応答(hook が記録)でのみ成立します。意図した操作か確認してください。"
fi
# 7) 計画未承認のあいだの保護領域への Bash 書込(guard-plan-approval.sh の Bash 版)。
if printf '%s' "$cmd" | grep -Eq '(>|>>|tee[[:space:]]|sed[[:space:]]+-i|cp[[:space:]]|mv[[:space:]])[^;&|]*(apps|services|packages|infra|contracts)/' \
   && [ -x "${CLAUDE_PROJECT_DIR:-.}/scripts/intent.sh" ] && d="$("${CLAUDE_PROJECT_DIR:-.}/scripts/intent.sh" active 2>/dev/null)" \
   && ! sed -n 's/^- Gate plan: //p' "$d/state.md" | grep -q '^approved'; then
  deny "計画が未承認です(intent $(basename "$d"))。apps/ services/ infra/ 等への書込は gate plan の承認後に行ってください。"
fi
# 8) ハーネス自体の改変は人間の確認を挟む(HITL-4)。Edit/Write 経由は guard-edit.sh が見る。
if printf '%s' "$cmd" | grep -Eq '(\.claude/(settings\.json|hooks/)|\.github/workflows/|policies/|lefthook\.yml|\.gitleaks\.toml)' && printf '%s' "$cmd" | grep -Eq '(>|>>|sed[[:space:]]+-i|tee[[:space:]]|mv[[:space:]]|rm[[:space:]]|cp[[:space:]]|python3?[[:space:]]+-|node[[:space:]]+-e)'; then
  ask "ハーネス自体(hooks / CI / policies / lefthook)を Bash で書き換えようとしています。意図した変更か確認してください。"
fi
exit 0
