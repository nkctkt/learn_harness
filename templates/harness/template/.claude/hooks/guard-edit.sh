#!/usr/bin/env bash
# PreToolUse(Edit|Write|MultiEdit): 書き込み先パスで判定する(Boundaries 層)。
#   deny: 秘密情報の置き場所、適用済みマイグレーション、lockfile の手編集
#   ask : ハーネス自体(hooks / settings / CI / policies)— HITL-4 として人間の確認を挟む
# 内容(秘密情報らしき文字列)の検査は guard-secrets.sh の責務。ここはパスだけ。
set -uo pipefail
command -v jq >/dev/null 2>&1 || exit 0
# hook 自身の実行時エラーで決定を返せない時に allow(fail-open)にならないよう、ERR で deny を返す。
# 構文エラーは trap 以前に exit 2 になり全ツールを block する(Exercise 04)。編集後は必ず bash -n を通すこと。
on_err() {
  jq -n --arg r "guard-edit.sh 自身がエラーで終了しました。hook を修正してください。" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}
trap on_err ERR
input="$(cat)"
path="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')"
[ -z "$path" ] && exit 0
root="${CLAUDE_PROJECT_DIR:-$(pwd)}"
rel="${path#"$root"/}"

decide() {
  jq -n --arg d "$1" --arg reason "$2" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:$d,permissionDecisionReason:$reason}}'
  exit 0
}

case "$rel" in
  .env|.env.*|*/.env|*/.env.*|secrets/*|*/secrets/*|*.pem|*.key|*id_rsa*|*id_ed25519*)
    [ "${rel##*/}" = ".env.example" ] || decide deny "秘密情報の置き場所には書き込めません: ${rel}。値は環境変数で渡し、例は .env.example にプレースホルダで書いてください。" ;;
  pnpm-lock.yaml|*/pnpm-lock.yaml|uv.lock|*/uv.lock|go.sum|*/go.sum)
    decide deny "lockfile は手で編集しません: ${rel}。pnpm / uv / go のコマンド経由で更新してください。" ;;
  apps/api/drizzle/*.sql)
    decide deny "生成済みマイグレーションは書き換えません: ${rel}。schema.ts を変更して drizzle-kit generate で新しいファイルを作ってください。" ;;
  docs/intents/*/state.md|docs/intents/*/audit.log)
    decide deny "intent の状態と監査ログは直接書きません: ${rel}。scripts/intent.sh(gate / stage / unit / note)経由で更新してください。承認(HUMAN_TURN)は hook だけが書きます。" ;;
  .claude/settings.json|.claude/hooks/*|.github/workflows/*|.github/rulesets/*|.github/CODEOWNERS|policies/*|lefthook.yml|.gitleaks.toml)
    decide ask "ハーネス自体を変更しようとしています(HITL-4): ${rel}。意図した変更か確認してください。" ;;
esac
exit 0
