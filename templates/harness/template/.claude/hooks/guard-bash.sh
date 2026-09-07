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

deny() {
  jq -n --arg reason "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$reason}}'
  exit 0
}
ask() {
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
# 6) ハーネス自体の改変は人間の確認を挟む(HITL-4)。Edit/Write 経由は guard-edit.sh が見る。
if printf '%s' "$cmd" | grep -Eq '(\.claude/(settings\.json|hooks/)|\.github/workflows/|policies/|lefthook\.yml|\.gitleaks\.toml)' && printf '%s' "$cmd" | grep -Eq '(>|>>|sed[[:space:]]+-i|tee[[:space:]]|mv[[:space:]]|rm[[:space:]]|cp[[:space:]]|python3?[[:space:]]+-|node[[:space:]]+-e)'; then
  ask "ハーネス自体(hooks / CI / policies / lefthook)を Bash で書き換えようとしています。意図した変更か確認してください。"
fi
exit 0
