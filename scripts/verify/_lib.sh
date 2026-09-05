#!/usr/bin/env bash
# 各言語スクリプト共通のヘルパー。
STEP_FAILED=0
step() {
  # step <name> <cmd...>: 実行して結果を 1 行で報告。失敗しても続行する。
  local name="$1"; shift
  local out
  if out="$("$@" 2>&1)"; then
    echo "  ✔ $name"
  else
    echo "  ✘ $name"; printf '%s\n' "$out" | sed 's/^/      /' | tail -n 60; STEP_FAILED=1
  fi
}
# 引数のファイル一覧を拡張子/パスで絞り込む。 filter_files <regex> files...
filter_files() { local re="$1"; shift; for f in "$@"; do [[ "$f" =~ $re ]] && echo "$f"; done; return 0; }
