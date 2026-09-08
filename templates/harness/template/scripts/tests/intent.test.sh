#!/usr/bin/env bash
# scripts/intent.sh の振る舞いテスト。一時ディレクトリを INTENTS_DIR にして実行する(リポジトリの記録は触らない)。
# 実行: scripts/tests/intent.test.sh   (verify.sh の docs 段からも呼ばれる)
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -r "$TMP"' EXIT     # allow-secret: 一時ディレクトリの後始末
export INTENTS_DIR="$TMP/intents"; mkdir -p "$INTENTS_DIR"
I="$ROOT/scripts/intent.sh"
fail=0; n=0
ok()   { n=$((n+1)); echo "  ✔ $1"; }
ng()   { n=$((n+1)); fail=1; echo "  ✘ $1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/      /'; }
expect_ok()   { local name="$1"; shift; local out; if out="$("$@" 2>&1)"; then ok "$name"; else ng "$name (expected success)" "$out"; fi; }
expect_fail() { local name="$1" want="$2"; shift 2; local out; if out="$("$@" 2>&1)"; then ng "$name (expected failure)" "$out"; elif printf '%s' "$out" | grep -q -- "$want"; then ok "$name"; else ng "$name (wrong message)" "$out"; fi; }
human() { "$I" human-turn test >/dev/null; }

echo "[intent.test]"
# --- 作成 -----------------------------------------------------------------------------------------
expect_fail "slug の形式を検査する" "slug は" "$I" new "Bad_Slug"
expect_fail "scope を検査する" "scope は" "$I" new demo --scope prod
expect_ok   "new で記録を作る" "$I" new demo --scope feature
D="$("$I" active)"
for f in state.md intent.md memory.md audit.log; do [ -f "$D/$f" ] && ok "$f が作られる" || ng "$f が無い"; done
expect_fail "active が 2 つになる new は拒否" "既にあります" "$I" new second

# --- 承認ゲート: 人間の在席が無い承認は拒否される -------------------------------------------------------
expect_fail "提示前の承認は拒否" "presented ではありません" "$I" gate approve intent
expect_ok   "gate present intent" "$I" gate present intent
expect_fail "提示直後(HUMAN_TURN 無し)の承認は拒否" "人間の応答" "$I" gate approve intent
human
expect_ok   "HUMAN_TURN の後は承認できる" "$I" gate approve intent
grep -q '^- Gate intent: approved ' "$D/state.md" && ok "state.md に承認時刻が入る" || ng "state.md の承認が無い"
expect_fail "古い HUMAN_TURN は再利用できない(再提示後に承認)" "人間の応答" bash -c "'$I' gate reject intent 'redo' >/dev/null && '$I' gate present intent >/dev/null && '$I' gate approve intent"
human; expect_ok "再提示 → 人間の応答 → 承認" "$I" gate approve intent

# --- 段階の順序: 計画承認前に construction へ進めない --------------------------------------------------
expect_fail "plan 未承認で construction は拒否" "gate plan の承認" "$I" stage construction
expect_ok   "stage inception" "$I" stage inception
expect_fail "plan.md が無い状態で gate present plan は拒否" "空です" "$I" gate present plan
cat > "$D/plan.md" <<'EOF'
# plan

## 分解(Units)

```yaml
units:
  - name: u1-skeleton
    depends_on: []
  - name: u2-feature
    depends_on: [u1-skeleton]
```

## 順序と walking skeleton

u1 が縦串。

## Definition of Done

- u1: /health が 200
EOF
expect_ok "gate present plan" "$I" gate present plan
expect_fail "unit start は construction でのみ" "stage construction" bash -c "'$I' unit add u1-skeleton 'x' >/dev/null && '$I' unit start u1-skeleton"
human; expect_ok "gate approve plan" "$I" gate approve plan
expect_ok "stage construction" "$I" stage construction
expect_ok "unit add" "$I" unit add u2-feature "feature"
expect_fail "unit id の形式" "形式" "$I" unit add bad "x"
expect_fail "start 前の done は拒否" "進行中の unit ではありません" "$I" unit done u1-skeleton
expect_ok "unit start" "$I" unit start u1-skeleton
expect_ok "unit done" "$I" unit done u1-skeleton
expect_fail "未完了 unit があると handoff は拒否" "未完了の unit" "$I" stage handoff
"$I" unit start u2-feature >/dev/null; "$I" unit done u2-feature >/dev/null
expect_ok "全 unit 完了で handoff" "$I" stage handoff

# --- memory.md --------------------------------------------------------------------------------------
expect_ok "note を追記" "$I" note Deviations "skipped X because Y"
awk '/^## Deviations/{f=1;next} /^## /{f=0} f' "$D/memory.md" | grep -q 'skipped X' && ok "note は該当節の末尾に入る" || ng "note の位置が違う" "$(cat "$D/memory.md")"
expect_fail "未知の見出しは拒否" "見出しは" "$I" note Random "x"

# --- close ----------------------------------------------------------------------------------------
expect_fail "retro.md が無いと close できない" "retro.md" "$I" close
echo "# retro" > "$D/retro.md"
expect_ok "retro 後に close" "$I" close
expect_ok "close 後は new できる" "$I" new next --scope bugfix
"$I" close --abandon >/dev/null

# --- check(CI): 正常な記録は通り、改竄は落ちる ---------------------------------------------------------
expect_ok "check: 正常な記録は通る" "$I" check
cp -R "$D" "$TMP/backup"
# 改竄 1: HUMAN_TURN を消す(Agent が自分で承認したことにする)
grep -v '	HUMAN_TURN	' "$D/audit.log" > "$D/audit.log.tmp" && mv "$D/audit.log.tmp" "$D/audit.log"
expect_fail "check: HUMAN_TURN 無しの承認を検出" "人間の応答" "$I" check
cp "$TMP/backup/audit.log" "$D/audit.log"
# 改竄 2: state.md だけ approved にする(audit.log に GATE_APPROVED が無い)
sed 's/^- Gate plan: .*/- Gate plan: approved 2026-01-01T00:00:00Z/' "$D/state.md" > "$D/s.tmp" && mv "$D/s.tmp" "$D/state.md"
grep -v '	GATE_APPROVED	plan$' "$D/audit.log" > "$D/audit.log.tmp" && mv "$D/audit.log.tmp" "$D/audit.log"
expect_fail "check: state.md と audit.log の不整合を検出" "最終イベント" "$I" check
cp "$TMP/backup/state.md" "$D/state.md"; cp "$TMP/backup/audit.log" "$D/audit.log"
# 改竄 3: 循環依存
sed 's/depends_on: \[\]/depends_on: [u2-feature]/' "$D/plan.md" > "$D/p.tmp" && mv "$D/p.tmp" "$D/plan.md"
expect_fail "check: unit の循環依存を検出" "cycle" "$I" check
sed 's/depends_on: \[u2-feature\]/depends_on: [u9-ghost]/' "$D/plan.md" > "$D/p.tmp" && mv "$D/p.tmp" "$D/plan.md"
expect_fail "check: 未宣言 unit への依存を検出" "undeclared" "$I" check
cp "$TMP/backup/plan.md" "$D/plan.md"
# 改竄 4: intent.md の必須節を消す
sed '/^## スコープ外/d' "$D/intent.md" > "$D/i.tmp" && mv "$D/i.tmp" "$D/intent.md"
expect_fail "check: intent.md の必須節の欠落を検出" "スコープ外" "$I" check

echo "  $n assertions, fail=$fail"
exit $fail
