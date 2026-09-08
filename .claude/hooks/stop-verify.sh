#!/usr/bin/env bash
# Stop: Agent が「完了」する前に、HEAD からの全変更に対して verify(format / lint / 型 / 変更パッケージのテスト)を走らせる。
# 失敗したら exit 2 でターン終了を block し、stderr の内容を Agent に渡して修正させる。
#
# これが「Agent がテストしたと言う」を「テストが実際に通った」に置き換える層。
# - PostToolUse hook(編集ファイルだけ)を素通りした経路(Bash heredoc 等)もここで捕まえる。
# - stop_hook_active が true の時は自分が block した再入なので、無限ループを避けるため何もしない
#   (Claude Code 側にも連続 block の上限がある)。
# - 変更が無ければ即終了。
set -uo pipefail
input="$(cat)"
if printf '%s' "$input" | jq -e '.stop_hook_active == true' >/dev/null 2>&1; then exit 0; fi
root="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "$root" || exit 0
if git diff --quiet HEAD -- . 2>/dev/null && [ -z "$(git ls-files --others --exclude-standard)" ]; then exit 0; fi
if out="$("$root/scripts/verify.sh" --changed 2>&1)"; then exit 0; fi
# block を記録する(Phase 10、improvement-plan H1)。detail は失敗した段。失敗しても判定(exit 2)は変えない。
failed="$(printf '%s\n' "$out" | sed -n 's/^✘ verify failed: //p' | head -n1)"
"$root/scripts/intent.sh" event STOP_BLOCK "${failed:-verify}" >/dev/null 2>&1 || true
{
  echo "完了前チェック(scripts/verify.sh --changed)が失敗しました。根本原因を直してから完了してください。"
  echo "テストの skip / 無効化、抑制コメント、閾値の緩和で通すことは禁止です。"
  echo
  printf '%s\n' "$out" | tail -n 80
} >&2
exit 2
