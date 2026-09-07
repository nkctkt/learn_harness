#!/usr/bin/env bash
# TypeScript / JS / JSON / CSS: Biome(format + lint)と tsc(型)。
# 責務: Biome は構文木のパターン、tsc はプログラム全体の型。Biome は型を見ないので両方必要。
set -uo pipefail
source "$(dirname "$0")/_lib.sh"
cd "$VERIFY_ROOT"
echo "[ts]"

if [ $# -eq 0 ]; then
  # 全体
  if [ "$VERIFY_FIX" = 1 ]; then step "biome check --write" pnpm exec biome check --write .
  else step "biome check" pnpm exec biome check .; fi
  step "tsc (all packages)" pnpm -r --workspace-concurrency=4 typecheck
  # 型情報 lint は全体の型解決が必要で遅いため、全体モード(CI / Stop hook)でのみ実行する
  step "eslint (type-aware rules only)" pnpm exec eslint .
  # テストは全体モードではカバレッジ付きで実行する(json-summary を CI の job summary に使う)。閾値では落とさない。
  step "vitest (all packages, coverage)" pnpm -r --workspace-concurrency=4 test:coverage
  # 契約(contracts/*.schema.json)が api の zod スキーマと一致していること(drift 検出)
  [ -n "${TS_CONTRACTS_FILTER:-}" ] && step "contracts:check (zod → JSON Schema drift)" pnpm --filter "$TS_CONTRACTS_FILTER" contracts:check
  # アーキテクチャ規約(レイヤー・循環)は lint も型も見ない。違反は error。
  step "dependency-cruiser (architecture rules)" pnpm exec depcruise --config .dependency-cruiser.cjs "${TS_ARCH_DIRS[@]}"
  # 未使用 export / 依存は警告のみ(AI が残しがちだが、false positive もあるので merge block にしない)
  if out="$(pnpm exec knip --no-progress 2>&1)"; then echo "  ✔ knip (dead code, warn-only)"; else echo "  ! knip (warn-only)"; printf '%s\n' "$out" | sed 's/^/      /' | tail -n 30; fi
  exit $STEP_FAILED
fi

# 差分モード: Biome は対象ファイルだけ、tsc は対象ファイルが属するパッケージだけ
files=(); while IFS= read -r _l; do files+=("$_l"); done < <(filter_files '\.(ts|tsx|js|jsx|mjs|cjs|json|jsonc|css)$' "$@")
[ ${#files[@]} -eq 0 ] && { echo "  - no ts files"; exit 0; }
if [ "$VERIFY_FIX" = 1 ]; then step "biome check --write (${#files[@]} files)" pnpm exec biome check --write "${files[@]}"
else step "biome check (${#files[@]} files)" pnpm exec biome check "${files[@]}"; fi

pkgs=(); while IFS= read -r _l; do pkgs+=("$_l"); done < <(for f in "${files[@]}"; do [[ "$f" =~ ^((apps|packages)/[^/]+)/.*\.(ts|tsx)$ ]] && echo "${BASH_REMATCH[1]}"; done | sort -u)
for p in "${pkgs[@]+"${pkgs[@]}"}"; do
  [ -f "$p/package.json" ] || continue
  step "tsc ($p)" pnpm --dir "$p" typecheck
  # 差分モードでは変更パッケージのテストだけを走らせる(カバレッジ無し。速度優先)。
  [ "${VERIFY_MODE}" = changed ] && step "vitest ($p)" pnpm --dir "$p" test
done
exit $STEP_FAILED
