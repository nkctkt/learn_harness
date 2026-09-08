#!/usr/bin/env bash
# ハーネスの「形」の検査(plan-reviewer の指摘 → 決定論的テストに変換、Exercise 12)。
#   1. 全 skill に frontmatter の name / description がある(無いと Claude Code が認識しない)
#   2. 全 .claude/rules/*.md に paths: がある(無いと常時読み込まれ、AGENTS.md の肥大化と同じになる)
#   3. 全 agent に name / description / tools がある
#   4. テンプレートと本体で「同一であるべきファイル」が byte 一致する(ドリフト検出)
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"
T=templates/harness/template
fail=0; n=0
ok() { n=$((n+1)); echo "  ✔ $1"; }
ng() { n=$((n+1)); fail=1; echo "  ✘ $1"; }
front() { awk 'NR==1 && $0!="---" {exit} NR>1 && $0=="---" {exit} NR>1 {print}' "$1"; }   # frontmatter 本体

echo "[harness-shape.test]"
for f in .claude/skills/*/SKILL.md; do
  fm="$(front "$f")"
  printf '%s\n' "$fm" | grep -q '^name: ' && printf '%s\n' "$fm" | grep -q '^description: ' && ok "skill frontmatter: $f" || ng "skill frontmatter (name/description) が無い: $f"
  [ "$(printf '%s\n' "$fm" | sed -n 's/^name: //p')" = "$(basename "$(dirname "$f")")" ] || ng "skill name とディレクトリ名が違う: $f"
done
for f in .claude/rules/*.md; do
  front "$f" | grep -q '^paths:' && ok "rule paths: $f" || ng "rule に paths: が無い(常時読込になる): $f"
done
for f in .claude/agents/*.md; do
  fm="$(front "$f")"
  printf '%s\n' "$fm" | grep -q '^name: ' && printf '%s\n' "$fm" | grep -q '^description: ' && printf '%s\n' "$fm" | grep -q '^tools: ' && ok "agent frontmatter: $f" || ng "agent frontmatter (name/description/tools) が無い: $f"
done
# 4. テンプレートとのドリフト。固有値を持つもの(targets.sh、sec.sh、security.yml、biome 等)は対象外(Exercise 11)。
if [ -d "$T" ]; then
  same=(.claude/hooks/*.sh .claude/skills/*/SKILL.md .claude/agents/*.md .claude/rules/harness.md .claude/rules/intents.md .claude/settings.json
        scripts/intent.sh scripts/tests/*.test.sh scripts/verify.sh scripts/verify/_lib.sh scripts/verify/ts.sh scripts/verify/py.sh scripts/verify/go.sh scripts/verify/infra.sh scripts/verify/docs.sh
        docs/intents/README.md lefthook.yml .gitleaks.toml)
  drift=""
  for f in "${same[@]}"; do
    [ -f "$T/$f" ] || { drift="$drift missing:$f"; continue; }
    cmp -s "$f" "$T/$f" || drift="$drift differs:$f"
  done
  [ -z "$drift" ] && ok "template drift: ${#same[@]} files identical" || ng "template drift(cp して同期する):$drift"
fi
echo "  $n assertions, fail=$fail"
exit $fail
