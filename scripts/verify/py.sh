#!/usr/bin/env bash
# Python: Ruff(format + lint)と basedpyright(型)。
# 責務: Ruff は構文木のパターン(S ルールで bandit 相当も)、basedpyright は型推論。
set -uo pipefail
source "$(dirname "$0")/_lib.sh"
cd "$VERIFY_ROOT"
unset VIRTUAL_ENV  # 他プロジェクトの venv が有効でも uv がプロジェクトの環境を使うように
echo "[py]"
PROJECTS=(services/enricher)

if [ $# -gt 0 ]; then
  files=(); while IFS= read -r _l; do files+=("$_l"); done < <(filter_files '\.(py|pyi)$' "$@")
  [ ${#files[@]} -eq 0 ] && { echo "  - no py files"; exit 0; }
fi

for proj in "${PROJECTS[@]}"; do
  if [ $# -gt 0 ]; then
    pf=(); while IFS= read -r _l; do pf+=("$_l"); done < <(for f in "${files[@]}"; do [[ "$f" == "$proj"/* ]] && echo "${f#"$proj"/}"; done)
    [ ${#pf[@]} -eq 0 ] && continue
  else
    pf=(.)
  fi
  pushd "$proj" >/dev/null
  if [ "$VERIFY_FIX" = 1 ]; then
    step "ruff format ($proj)" uv run --quiet ruff format "${pf[@]}"
    step "ruff check --fix ($proj)" uv run --quiet ruff check --fix "${pf[@]}"
  else
    step "ruff format --check ($proj)" uv run --quiet ruff format --check "${pf[@]}"
    step "ruff check ($proj)" uv run --quiet ruff check "${pf[@]}"
  fi
  step "basedpyright ($proj)" uv run --quiet basedpyright
  # pytest は pyproject の addopts でカバレッジを常に出す(数十 ms)。--files(単一ファイル編集)では走らせない。
  [ "${VERIFY_MODE}" != files ] && step "pytest ($proj)" uv run --quiet pytest
  # アーキテクチャ規約(import-linter)。全体モードのみ。
  [ "${VERIFY_MODE}" = all ] && step "import-linter ($proj)" uv run --quiet lint-imports
  popd >/dev/null
done
exit $STEP_FAILED
