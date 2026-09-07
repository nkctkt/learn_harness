#!/usr/bin/env bash
# .github/rulesets/*.json を GitHub Rulesets として適用する(Rulesets as code)。
# 同名の ruleset があれば更新、無ければ作成。要: gh auth login 済み、repo admin 権限。
set -euo pipefail
repo="${1:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
for f in "$(dirname "$0")/../../.github/rulesets"/*.json; do
  name="$(jq -r .name "$f")"
  id="$(gh api "repos/$repo/rulesets" --jq ".[] | select(.name==\"$name\") | .id" || true)"
  if [ -n "$id" ]; then
    gh api -X PUT "repos/$repo/rulesets/$id" --input "$f" >/dev/null && echo "updated $name (#$id)"
  else
    gh api -X POST "repos/$repo/rulesets" --input "$f" --jq '.id' | xargs -I{} echo "created $name (#{})"
  fi
done
