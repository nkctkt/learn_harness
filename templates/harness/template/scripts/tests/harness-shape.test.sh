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
# 3b. /retro の計測欄はハーネスの判定回数を読む(Phase 10、improvement-plan H1。retro で摩擦を数えない経路を塞ぐ)
r=.claude/skills/retro/SKILL.md
grep -q 'intent.sh metrics' "$r" && grep -q 'deny' "$r" && grep -q 'Stop block' "$r" && ok "retro skill が intent.sh metrics(deny / Stop block)を読む" || ng "retro skill の計測欄に metrics / deny / Stop block が無い: $r"
# 3c. ゲートは [gate <g>] 付きの AskUserQuestion で出す(Phase 10 H2。テキスト提示は承認にならないので、手順がそう書いていることを検査する)
for pair in intent:intent plan-units:plan; do
  sk="${pair%%:*}"; g="${pair##*:}"; f=".claude/skills/$sk/SKILL.md"
  if grep -q 'AskUserQuestion' "$f" && grep -q "\[gate $g\]" "$f"; then ok "skill $sk のゲート手順に AskUserQuestion と [gate $g] がある"; else ng "skill $sk のゲート手順に AskUserQuestion / [gate $g] が無い: $f"; fi
done
grep -q '\[gate' .claude/rules/intents.md && ok "rules/intents.md がゲートの印([gate)を説明する" || ng "rules/intents.md に [gate の説明が無い"
grep -q 'answer=Approve' docs/lifecycle.md && ok "lifecycle.md が同意の受領証(answer=Approve)を説明する" || ng "lifecycle.md に answer=Approve の説明が無い"
# 3d. bash 3.2 の罠: 変数名の直後に非 ASCII(`$a、` は変数 `a、` になり unbound variable)。rules に書いても 2 度踏んだので検査にする(Phase 10 H2 の retro)
bad="$(grep -nE '\$[A-Za-z_][A-Za-z0-9_]*[^[:print:][:space:]]' .claude/hooks/*.sh scripts/*.sh scripts/verify/*.sh scripts/tests/*.sh 2>/dev/null | grep -vE '\$\{' | head -n5 || true)"
[ -z "$bad" ] && ok "変数の直後に非 ASCII が無い(\${a} と書く)" || ng "変数の直後に非 ASCII(bash 3.2 で変数名に含まれる): $bad"
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
