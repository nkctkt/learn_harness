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
human() { "$I" human-turn UserPromptSubmit >/dev/null; }                                              # 在席のみ(承認には使えない)
approve() { "$I" human-turn "PostToolUse:AskUserQuestion answer=Approve gate=$1" >/dev/null; }          # [gate $1] への Approve
reject()  { "$I" human-turn "PostToolUse:AskUserQuestion answer=Request Changes gate=$1" >/dev/null; }

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
grep -q '^- Receipt: consent$' "$D/state.md" && ok "new は state.md に Receipt: consent を書く" || ng "Receipt が無い"
expect_fail "consent: 提示直後(回答無し)の承認は拒否" "gate intent" "$I" gate approve intent
human
expect_fail "consent: UserPromptSubmit だけでは承認できない(理由に AskUserQuestion と [gate intent])" "\[gate intent\]" "$I" gate approve intent
reject intent
expect_fail "consent: Request Changes では承認できない" "Approve ではありません" "$I" gate approve intent
approve plan
expect_fail "consent: 別ゲート(plan)の Approve では intent を承認できない(intent 宛ての最新は Request Changes のまま)" "Approve ではありません" "$I" gate approve intent
approve intent
expect_ok   "consent: [gate intent] への Approve で承認できる(Request Changes の後の Approve が最新)" "$I" gate approve intent
grep -q '^- Gate intent: approved ' "$D/state.md" && ok "state.md に承認時刻が入る" || ng "state.md の承認が無い"
expect_fail "古い Approve は再利用できない(再提示後に承認)" "回答がありません" bash -c "'$I' gate reject intent 'redo' >/dev/null && '$I' gate present intent >/dev/null && '$I' gate approve intent"
approve intent; human
expect_ok "consent: Approve の後に人間が発言(UserPromptSubmit)しても承認できる" "$I" gate approve intent
expect_fail "consent: Approve の後に Request Changes が来ると承認できない" "Approve ではありません" bash -c "'$I' gate reject intent 'again' >/dev/null && '$I' gate present intent >/dev/null && '$I' human-turn 'PostToolUse:AskUserQuestion answer=Approve gate=intent' >/dev/null && '$I' human-turn 'PostToolUse:AskUserQuestion answer=Request Changes gate=intent' >/dev/null && '$I' gate approve intent"
approve intent; expect_ok "再提示 → Approve → 承認" "$I" gate approve intent

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
approve plan; expect_ok "gate approve plan" "$I" gate approve plan
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

# --- event / metrics(Phase 10: ハーネスの判定を記録して数える)-------------------------------------------
export HARNESS_METRICS_LOG="$TMP/metrics.log"
expect_ok   "event は active intent の audit.log に追記する" "$I" event HOOK_DENY "guard-bash: rm"
grep -q '	HOOK_DENY	guard-bash: rm$' "$D/audit.log" && ok "event は TSV(ts / event / detail)で書かれる" || ng "event の形式" "$(tail -n2 "$D/audit.log")"
expect_fail "event 名は大文字英字と _ のみ" "event 名" "$I" event bad-name "x"
expect_fail "event は detail が必要" "detail" "$I" event HOOK_DENY
"$I" event HOOK_ASK "$(printf 'a\tb\nc')" >/dev/null
grep -q '	HOOK_ASK	a b c$' "$D/audit.log" && ok "event: detail のタブ / 改行はスペースに正規化される(TSV の列を壊さない)" || ng "detail のサニタイズ" "$(tail -n1 "$D/audit.log")"
"$I" event HOOK_ASK "$(printf 'x%.0s' $(seq 1 200))" >/dev/null
[ "$(tail -n1 "$D/audit.log" | cut -f3 | wc -c | tr -d ' ')" -eq 121 ] && ok "event: detail は 120 文字に切られる" || ng "detail の切り詰め" "$(tail -n1 "$D/audit.log" | cut -f3 | wc -c)"
for e in "HOOK_DENY guard-edit: y" "HOOK_ASK guard-bash: z" "STOP_BLOCK ts" "POST_EDIT_FAIL apps/api/src/a.ts"; do "$I" event $e >/dev/null; done
expect_ok   "check: hook イベントを含む audit.log を通す(受領証の順序検査に影響しない)" "$I" check
out="$("$I" metrics)"
printf '%s\n' "$out" | grep -Eq '^HOOK_DENY	2$'      && ok "metrics: HOOK_DENY を数える"      || ng "metrics: HOOK_DENY" "$out"
printf '%s\n' "$out" | grep -Eq '^HOOK_ASK	3$'       && ok "metrics: HOOK_ASK を数える"       || ng "metrics: HOOK_ASK" "$out"
printf '%s\n' "$out" | grep -Eq '^STOP_BLOCK	1$'     && ok "metrics: STOP_BLOCK を数える"     || ng "metrics: STOP_BLOCK" "$out"
printf '%s\n' "$out" | grep -Eq '^POST_EDIT_FAIL	1$' && ok "metrics: POST_EDIT_FAIL を数える" || ng "metrics: POST_EDIT_FAIL" "$out"
printf '%s\n' "$out" | grep -Eq '^HUMAN_TURN	[1-9]'  && ok "metrics: HUMAN_TURN を数える"     || ng "metrics: HUMAN_TURN" "$out"
printf '%s\n' "$out" | grep -Eq '^GATE_REJECTED	2$'  && ok "metrics: GATE_REJECTED を数える"  || ng "metrics: GATE_REJECTED" "$out"
printf '%s\n' "$out" | grep -Eq '^elapsed_sec	[0-9]+$' && ok "metrics: 経過秒を出す(未 close は現在まで)" || ng "metrics: elapsed" "$out"
printf '2026-09-08T00:00:00Z\tINTENT_CREATED\tscope=feature\n2026-09-08T01:30:00Z\tINTENT_CLOSED\tcompleted\n' > "$TMP/fixed.log"
out="$("$I" metrics --file "$TMP/fixed.log")"
printf '%s\n' "$out" | grep -Eq '^elapsed_sec	5400$' && ok "metrics: iso_to_epoch(00:00 → 01:30 = 5400 秒、GNU / BSD date 両対応)" || ng "metrics: elapsed 計算" "$out"
grep -qx '.claude/metrics.log' "$ROOT/.gitignore" && ok ".gitignore に .claude/metrics.log がある" || ng ".gitignore に .claude/metrics.log が無い"

# --- legacy(Receipt 無し、Phase 9 の記録)は従来の規則 --------------------------------------------------------
expect_ok "check: 本物の docs/intents(旧形式 2 件 + 進行中)は通る" env INTENTS_DIR="$ROOT/docs/intents" "$I" check

# --- close ----------------------------------------------------------------------------------------
expect_fail "retro.md が無いと close できない" "retro.md" "$I" close
echo "# retro" > "$D/retro.md"
expect_ok "retro 後に close" "$I" close
expect_ok "close 後は new できる" "$I" new next --scope bugfix
"$I" close --abandon >/dev/null

# --- metrics: HUMAN_TURN の厳密な件数(新しい intent で既知の回数だけ記録する)-------------------------------
"$I" new counter --scope feature >/dev/null; human; human
out="$("$I" metrics)"
printf '%s\n' "$out" | grep -Eq '^HUMAN_TURN	2$' && ok "metrics: HUMAN_TURN を正確に数える(2 回 → 2)" || ng "metrics: HUMAN_TURN の件数" "$out"
"$I" close --abandon >/dev/null

# --- halt-reason: Stop hook が verify を skip してよい理由(ADR-0002。600 秒の窓、窓内 3 回)----------------------
expect_fail "halt-reason: intent が無ければ exit 1" "" bash -c "'$I' halt-reason; [ \$? -ne 0 ] && echo no-reason && exit 1"
"$I" new halt --scope feature >/dev/null; HD="$("$I" active)"
"$I" halt-reason >/dev/null 2>&1 && ng "halt-reason: 提示も note も無いのに理由が出た" || ok "halt-reason: 提示も note も無ければ exit 1"
"$I" gate present intent >/dev/null
[ "$("$I" halt-reason)" = "gate=intent" ] && ok "halt-reason: gate presented(600 秒以内)で gate=intent" || ng "halt-reason gate" "$("$I" halt-reason)"
age() { sed "s/^[0-9T:Z-]*\(	$1\)/2020-01-01T00:00:00Z\1/" "$HD/audit.log" > "$HD/a.tmp" && mv "$HD/a.tmp" "$HD/audit.log"; }   # age <event 列の正規表現>: 該当行の時刻を過去にする
age 'GATE_PRESENTED	intent'
"$I" halt-reason >/dev/null 2>&1 && ng "halt-reason: 601 秒前の提示で理由が出た" || ok "halt-reason: GATE_PRESENTED が 600 秒より古ければ exit 1"
"$I" note "Open questions" "DoD が満たせない" >/dev/null
[ "$("$I" halt-reason)" = "open-questions" ] && ok "halt-reason: Open questions の note 直後は open-questions" || ng "halt-reason note" "$("$I" halt-reason)"
"$I" gate reject intent "redo" >/dev/null; "$I" gate present intent >/dev/null
[ "$("$I" halt-reason)" = "gate=intent" ] && ok "halt-reason: 提示と note が両方あれば gate= を優先" || ng "halt-reason 優先" "$("$I" halt-reason)"
age 'GATE_PRESENTED	intent'; age 'NOTE	Open questions'
"$I" halt-reason >/dev/null 2>&1 && ng "halt-reason: 古い note で理由が出た" || ok "halt-reason: note が 600 秒より古ければ exit 1"
"$I" note "Open questions" "again" >/dev/null
for _ in 1 2 3; do "$I" event STOP_SKIP open-questions >/dev/null; done
"$I" halt-reason >/dev/null 2>&1 && ng "halt-reason: 上限 3 回を超えて理由が出た" || ok "halt-reason: 600 秒以内に STOP_SKIP が 3 件あれば exit 1(上限)"
ln="$(grep -n '	STOP_SKIP	' "$HD/audit.log" | head -n1 | cut -d: -f1)"   # 最初の STOP_SKIP だけ古くする(BSD / GNU 共通の行番号指定)
sed "${ln}s/^[0-9T:Z-]*/2020-01-01T00:00:00Z/" "$HD/audit.log" > "$HD/a.tmp" && mv "$HD/a.tmp" "$HD/audit.log"
[ "$("$I" halt-reason)" = "open-questions" ] && ok "halt-reason: 600 秒より古い STOP_SKIP は上限に数えない(2 件なら skip 可)" || ng "halt-reason 上限の窓" "$(grep STOP_SKIP "$HD/audit.log")"
"$I" close --abandon >/dev/null

# --- legacy(state.md に Receipt 無し)は UserPromptSubmit で承認できる ------------------------------------------
"$I" new legacy --scope feature >/dev/null; L="$("$I" active)"
grep -v '^- Receipt: ' "$L/state.md" > "$L/s.tmp" && mv "$L/s.tmp" "$L/state.md"
"$I" gate present intent >/dev/null
expect_fail "legacy: 在席(HUMAN_TURN)が無ければ承認できない(旧規則も人間ゼロは拒否)" "人間の応答" "$I" gate approve intent
human
expect_ok "legacy: Receipt 無しの intent は在席(UserPromptSubmit)だけで承認できる" "$I" gate approve intent
expect_ok "check: legacy の承認は通る" "$I" check
"$I" close --abandon >/dev/null

# --- event / metrics: intent が無い時はローカルの metrics.log(Git 追跡外)に書く --------------------------
expect_ok "event は intent が無ければ metrics.log に追記する" "$I" event HOOK_DENY "guard-bash: no intent"
grep -q '	HOOK_DENY	guard-bash: no intent$' "$HARNESS_METRICS_LOG" && ok "metrics.log も同じ TSV 形式" || ng "metrics.log の形式" "$(cat "$HARNESS_METRICS_LOG" 2>&1)"
out="$("$I" metrics)"   # パイプに直接つなぐと grep -q の早期終了 + pipefail で偽の失敗になる
printf '%s\n' "$out" | grep -Eq '^HOOK_DENY	1$' && ok "metrics は intent が無ければ metrics.log を読む" || ng "metrics の読み先" "$out"

# --- check(CI): 正常な記録は通り、改竄は落ちる ---------------------------------------------------------
expect_ok "check: 正常な記録は通る" "$I" check
cp -R "$D" "$TMP/backup"
# 改竄 1: HUMAN_TURN を消す(Agent が自分で承認したことにする)
grep -v '	HUMAN_TURN	' "$D/audit.log" > "$D/audit.log.tmp" && mv "$D/audit.log.tmp" "$D/audit.log"
expect_fail "check: HUMAN_TURN 無しの承認を検出" "Approve" "$I" check
cp "$TMP/backup/audit.log" "$D/audit.log"
# 改竄 1b: Approve を在席(UserPromptSubmit)に書き換える(consent では承認にならない)
sed 's/	HUMAN_TURN	PostToolUse:AskUserQuestion answer=Approve gate=plan$/	HUMAN_TURN	UserPromptSubmit/' "$D/audit.log" > "$D/audit.log.tmp" && mv "$D/audit.log.tmp" "$D/audit.log"
expect_fail "check: consent の承認が在席だけで行われた改竄を検出" "\[gate plan\] への Approve" "$I" check
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
