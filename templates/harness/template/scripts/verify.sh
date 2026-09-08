#!/usr/bin/env bash
# hooks と CI が共有する唯一の検証エントリポイント。
#
#   scripts/verify.sh                 # 全体(CI で使う)
#   scripts/verify.sh --changed       # HEAD からの変更ファイルのみ(Stop hook / pre-commit で使う)
#   scripts/verify.sh --files a b c   # 指定ファイルのみ(PostToolUse hook で使う)
#   scripts/verify.sh --fix ...       # formatter / lint の自動修正を適用する(hook 用。CI では使わない)
#   scripts/verify.sh --only ts,py    # 段を限定(ts / py / go / sec / infra / docs)
#
# 設計原則: 同じスクリプトを「範囲だけ変えて」全層から呼ぶ。Hook は速い部分集合、CI は全体。
# 各ステップは失敗しても止まらず最後まで走り、最後にまとめて非 0 で終了する(1 回で全部の指摘を返す)。
set -uo pipefail
[ "${BASH_VERSINFO[0]}" -ge 3 ] || { echo "bash >= 3.2 required" >&2; exit 70; }
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

MODE=all; FIX=0; ONLY=""; FILES=()
while [ $# -gt 0 ]; do
  case "$1" in
    --changed) MODE=changed ;;
    --files) MODE=files; shift; while [ $# -gt 0 ] && [[ "$1" != --* ]]; do FILES+=("$1"); shift; done; continue ;;
    --fix) FIX=1 ;;
    --only) shift; ONLY="$1" ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
  shift
done

if [ "$MODE" = changed ]; then
  # 変更済み(staged / unstaged)と未追跡のファイル。削除されたものは除く。
  FILES=(); while IFS= read -r _l; do FILES+=("$_l"); done < <({ git diff --name-only HEAD; git ls-files --others --exclude-standard; } | sort -u | while read -r f; do [ -f "$f" ] && echo "$f"; done)
  if [ ${#FILES[@]} -eq 0 ]; then echo "verify: no changed files"; exit 0; fi
fi

# 絶対パスを repo 相対に正規化
if [ ${#FILES[@]} -gt 0 ]; then
  for i in "${!FILES[@]}"; do FILES[$i]="${FILES[$i]#"$ROOT"/}"; done
fi

export VERIFY_ROOT="$ROOT" VERIFY_MODE="$MODE" VERIFY_FIX="$FIX"
FAILED=()
run_lang() {
  local lang="$1"
  if [ -n "$ONLY" ] && [[ ",$ONLY," != *",$lang,"* ]]; then return; fi
  if ! "$ROOT/scripts/verify/$lang.sh" "${FILES[@]+"${FILES[@]}"}"; then FAILED+=("$lang"); fi
}
run_lang ts
run_lang py
run_lang go
run_lang sec
run_lang infra
run_lang docs

echo
if [ ${#FAILED[@]} -gt 0 ]; then
  echo "✘ verify failed: ${FAILED[*]}" >&2; exit 1
fi
echo "✔ verify passed (mode=$MODE)"
