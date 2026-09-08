#!/usr/bin/env bash
# intent.sh — 開発ライフサイクルの「記録」と「承認ゲート」を扱う唯一の入口(Phase 9、AI-DLC の状態機械の最小再実装)。
#
#   scripts/intent.sh new <slug> [--scope feature|bugfix|refactor|harness]   intent を作る(docs/intents/<YYMMDD>-<slug>/)
#   scripts/intent.sh active | status                                        有効な intent のパス / 要約
#   scripts/intent.sh gate present <intent|plan>                             ゲートを提示した(このあとターンを終えて人間を待つ)
#   scripts/intent.sh gate approve <intent|plan>                             [gate <g>] AskUserQuestion への最新の回答が Approve なら承認を記録
#   scripts/intent.sh gate reject  <intent|plan> "<reason>"                  差し戻し
#   scripts/intent.sh stage <ideation|inception|construction|handoff|operation>
#   scripts/intent.sh unit add <id> "<desc>" | start <id> | done <id>
#   scripts/intent.sh note <Interpretations|Deviations|Tradeoffs|Open questions> "<text>"   memory.md に追記
#   scripts/intent.sh close [--abandon]                                      intent を終える
#   scripts/intent.sh human-turn <source>                                    hook 専用: 人間の在席を記録
#   scripts/intent.sh event <EVENT> "<detail>"                               hook 専用: 判定(HOOK_DENY / HOOK_ASK / STOP_BLOCK / POST_EDIT_FAIL)を記録
#   scripts/intent.sh metrics [--file <log>]                                 判定・在席・差し戻しの回数と経過秒(/retro が読む)
#   scripts/intent.sh halt-reason                                            hook 専用: Stop hook が verify を skip してよい理由(ADR-0002)
#   scripts/intent.sh check                                                  全 intent の整合性検査(CI の docs 段)
#
# 設計:
#   - 状態は docs/intents/<id>/state.md(人が読める)と audit.log(追記専用、TSV: ts / event / detail)。両方 Git に入れる。
#   - 承認の受領証(HUMAN_TURN)は hook(UserPromptSubmit / AskUserQuestion)だけが書く。Agent は gate approve で「読む」だけ。
#     → 提示(GATE_PRESENTED)より後に HUMAN_TURN が無ければ承認できない。Agent が自分で承認を捏造する経路を塞ぐ。
#   - Receipt: consent の intent(Phase 10 H2 以降に new で作ったもの)は、[gate <g>] 付き AskUserQuestion への
#     最新の回答が answer=Approve でなければ承認できない(在席ではなく同意)。Receipt 無しの旧記録は従来の規則。
#   - state.md / audit.log への直接書込は guard-edit.sh が deny、Bash 経由は guard-bash.sh が ask にする。
#   - ローカルの記録は改竄できる(全ローカル層と同じ)。check を CI で回して、改竄を PR で露見させる。
#   - ハーネスの判定(deny / ask / Stop block)は hook が `event` で記録する(Phase 10、improvement-plan H1)。
#     active な intent があれば audit.log、無ければ .claude/metrics.log(Git 追跡外、check の対象外。intent 外の摩擦を見るだけ)。
#   - bash 3.2(macOS)で動く。jq / python に依存しない。
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INTENTS_DIR="${INTENTS_DIR:-$ROOT/docs/intents}"
METRICS_LOG="${HARNESS_METRICS_LOG:-$ROOT/.claude/metrics.log}"
now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
iso_to_epoch() {
  # ISO-8601(UTC、秒精度)→ epoch 秒。GNU date(CI の ubuntu)を先に試し、BSD date(macOS)に落とす。
  date -u -d "$1" +%s 2>/dev/null || date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$1" +%s 2>/dev/null
}
die() { echo "intent: $*" >&2; exit 1; }
usage() { sed -n '2,15p' "$0"; exit 64; }

# ---- 状態ファイルの読み書き --------------------------------------------------------------------
active_dir() {
  # Status: active の intent を 1 つだけ許す。0 なら exit 1、2 以上は異常。
  local d found=""
  for d in "$INTENTS_DIR"/*/; do
    [ -f "$d/state.md" ] || continue
    if grep -q '^- Status: active$' "$d/state.md"; then
      [ -n "$found" ] && die "active な intent が複数あります: $found $d(片方を close してください)"
      found="${d%/}"
    fi
  done
  [ -n "$found" ] || return 1
  printf '%s\n' "$found"
}
field() { sed -n "s/^- $1: //p" "$2/state.md" | head -n1; }   # field <key> <dir>
set_field() {                                                # set_field <key> <value> <dir>
  local tmp="$3/state.md.tmp"
  sed "s|^- $1: .*|- $1: $2|" "$3/state.md" > "$tmp" && mv "$tmp" "$3/state.md"
}
audit() { printf '%s\t%s\t%s\n' "$(now)" "$1" "${2:-}" >> "$3/audit.log"; }   # audit <event> <detail> <dir>
last_line_no() { grep -n "	$1	$2" "$3/audit.log" | tail -n1 | cut -d: -f1; }   # last_line_no <event> <detail-prefix> <dir>

# ---- new --------------------------------------------------------------------------------------
cmd_new() {
  local slug="${1:-}"; shift || true
  local scope=feature
  while [ $# -gt 0 ]; do case "$1" in --scope) scope="$2"; shift ;; *) die "unknown arg: $1" ;; esac; shift; done
  [ -n "$slug" ] || usage
  printf '%s' "$slug" | grep -Eq '^[a-z][a-z0-9-]{1,40}$' || die "slug は小文字英数字とハイフン: $slug"
  case "$scope" in feature|bugfix|refactor|harness) ;; *) die "scope は feature|bugfix|refactor|harness: $scope" ;; esac
  if a="$(active_dir)"; then die "active な intent が既にあります: ${a}。先に close してください"; fi
  local id="$(date -u +%y%m%d)-$slug" dir
  dir="$INTENTS_DIR/$id"
  [ -e "$dir" ] && die "既に存在します: $dir"
  mkdir -p "$dir"
  cat > "$dir/state.md" <<EOF
# Intent: $id

- Status: active
- Scope: $scope
- Stage: ideation
- Gate intent: pending
- Gate plan: pending
- Receipt: consent
- Created: $(now)

## Units

EOF
  cat > "$dir/intent.md" <<EOF
# $id

- Scope: $scope
- 作成: $(date -u +%Y-%m-%d)

## 目的

(何を、誰のために、なぜ。1 段落)

## スコープ外

- (やらないことを明示する。後で「ついで」に膨らむのを防ぐ)

## 受け入れ条件

- [ ] AC1: (検証可能な文で。テスト名や verify の段に対応づける)

## リスクと HITL レベル

- 触れる信頼境界: (認証 / SQL / 外部 fetch / infra / ハーネス自体 / なし)
- HITL: 3(通常の PR)| 4(CODEOWNERS 承認: .github .claude policies infra 依存追加)| 5(人間のみ)
- 想定されるリスク:
EOF
  cat > "$dir/memory.md" <<'EOF'
# memory — この intent で起きたこと(/retro が読む)

各項目は `scripts/intent.sh note <見出し> "<本文>"` で追記する(ISO 時刻付き)。

## Interpretations
(曖昧だった指示をどう解釈したか)

## Deviations
(計画や手順から意図的に外れた点と理由)

## Tradeoffs
(検討した代替と選ばなかった理由)

## Open questions
(次に人間に確認すべきこと)
EOF
  : > "$dir/audit.log"
  audit INTENT_CREATED "scope=$scope" "$dir"
  echo "created: $dir"
  echo "次: $dir/intent.md を埋めて、scripts/intent.sh gate present intent → ターンを終えて人間の承認を待つ"
}

# ---- status -----------------------------------------------------------------------------------
cmd_status() {
  local dir
  dir="$(active_dir)" || { echo "active な intent はありません(scripts/intent.sh new <slug> で作る)"; return 0; }
  echo "intent: $(basename "$dir")  scope=$(field Scope "$dir")  stage=$(field Stage "$dir")"
  echo "gates : intent=$(field 'Gate intent' "$dir")  plan=$(field 'Gate plan' "$dir")"
  local total done_
  total="$(grep -c '^- \[.\] ' "$dir/state.md" || true)"; done_="$(grep -c '^- \[x\] ' "$dir/state.md" || true)"
  echo "units : $done_/$total done"
  grep '^- \[[ x-]\] ' "$dir/state.md" | sed 's/^/  /' || true
  echo "audit (last 3):"; tail -n3 "$dir/audit.log" | sed 's/^/  /'
  echo "next  :"
  case "$(field Stage "$dir")" in
    ideation)     [ "$(field 'Gate intent' "$dir")" = pending ] && echo "  intent.md を埋めて gate present intent" || echo "  人間の承認を待つ → gate approve intent → stage inception → /plan-units" ;;
    inception)    [ "$(field 'Gate plan' "$dir")" = pending ] && echo "  plan.md を書いて plan-reviewer → gate present plan" || echo "  人間の承認を待つ → gate approve plan → stage construction → /build-unit" ;;
    construction) echo "  未完了の unit を /build-unit で進める。全て [x] になったら stage handoff → /create-pr" ;;
    handoff)      echo "  PR の CI と人間レビュー。merge 後 stage operation または /retro → close" ;;
    operation)    echo "  /release または /incident。終わったら /retro → close" ;;
  esac
}

# ---- gate -------------------------------------------------------------------------------------
cmd_gate() {
  local action="${1:-}" name="${2:-}" reason="${3:-}" dir
  case "$name" in intent|plan) ;; *) die "gate 名は intent|plan: '$name'" ;; esac
  dir="$(active_dir)" || die "active な intent がありません"
  case "$action" in
    present)
      [ -s "$dir/$name.md" ] || die "$dir/$name.md が空です。提示する前に中身を書いてください"
      set_field "Gate $name" presented "$dir"; audit GATE_PRESENTED "$name" "$dir"
      if [ "$(field Receipt "$dir")" = consent ]; then
        echo "gate '$name' を提示しました。質問文に [gate $name] を含む AskUserQuestion(Approve / Request Changes の 2 択)で人間に聞き、回答が返った同じターンで gate approve / reject を呼んでください。テキストの返答は承認になりません。"
      else
        echo "gate '$name' を提示しました。**ここでターンを終えて**人間の応答を待ってください(Approve / Request Changes の 2 択)。"
      fi ;;
    approve)
      [ "$(field "Gate $name" "$dir")" = presented ] || die "gate '$name' は presented ではありません(現在: $(field "Gate $name" "$dir"))。先に gate present"
      local p h
      p="$(last_line_no GATE_PRESENTED "$name" "$dir")"; [ -n "$p" ] || die "監査ログに GATE_PRESENTED $name がありません"
      if [ "$(field Receipt "$dir")" = consent ]; then
        # 同意の受領証(Phase 10 H2): 提示より後の、このゲート宛て(gate=<name>)の回答のうち最新が Approve であること。
        # gate= の無い HUMAN_TURN(UserPromptSubmit、曖昧点確認の回答)は無視する。Approve の後に人間が発言しても詰まらない。
        local last; last="$(tail -n +"$((p+1))" "$dir/audit.log" | grep "	HUMAN_TURN	.* gate=$name\$" | tail -n1 | cut -f3)"
        case "$last" in
          *"answer=Approve gate=$name") ;;
          "") die "承認できません: gate '$name' を提示した後に、この gate 宛ての回答がありません。質問文に [gate $name] を含む AskUserQuestion(Approve / Request Changes)で人間に聞き、回答が返った同じターンで gate approve を呼んでください。テキストの返答は承認になりません。" ;;
          *) die "承認できません: gate '$name' への最新の回答は Approve ではありません($last)。直して gate present $name からやり直してください。" ;;
        esac
      else
        # 旧形式(Receipt 無し、Phase 9 の記録): 提示より後に人間の応答があればよい
        h="$(grep -n '	HUMAN_TURN	' "$dir/audit.log" | tail -n1 | cut -d: -f1)"
        if [ -z "$h" ] || [ "$h" -le "$p" ]; then
          die "承認できません: gate '$name' を提示した後に人間の応答(HUMAN_TURN)が記録されていません。ターンを終えて人間の返答を待ってください。Agent が自分で承認することはできません。"
        fi
      fi
      set_field "Gate $name" "approved $(now)" "$dir"; audit GATE_APPROVED "$name" "$dir"
      echo "gate '$name' approved."
      [ "$name" = intent ] && echo "次: scripts/intent.sh stage inception → /plan-units"
      [ "$name" = plan ] && echo "次: scripts/intent.sh stage construction → /build-unit <unit-id>"
      return 0 ;;
    reject)
      [ -n "$reason" ] || die "理由が必要です: gate reject $name \"<reason>\""
      set_field "Gate $name" pending "$dir"; audit GATE_REJECTED "$name: $reason" "$dir"
      echo "gate '$name' rejected: $reason(直して gate present $name をやり直す)" ;;
    *) usage ;;
  esac
}

# ---- stage / unit / note / close --------------------------------------------------------------
cmd_stage() {
  local to="${1:-}" dir; dir="$(active_dir)" || die "active な intent がありません"
  case "$to" in
    ideation) ;;
    inception)    [[ "$(field 'Gate intent' "$dir")" == approved* ]] || die "inception へ進むには gate intent の承認が必要です" ;;
    construction) [[ "$(field 'Gate plan' "$dir")" == approved* ]] || die "construction へ進むには gate plan の承認が必要です(計画を先に、コードは後に)" ;;
    handoff)      grep -q '^- \[[ -]\] ' "$dir/state.md" && die "未完了の unit があります。全て done にしてから handoff へ" ;;
    operation) ;;
    *) die "stage は ideation|inception|construction|handoff|operation: '$to'" ;;
  esac
  local from; from="$(field Stage "$dir")"
  set_field Stage "$to" "$dir"; audit STAGE_SET "$from -> $to" "$dir"; echo "stage: $from -> $to"
}
cmd_unit() {
  local action="${1:-}" id="${2:-}" desc="${3:-}" dir; dir="$(active_dir)" || die "active な intent がありません"
  printf '%s' "$id" | grep -Eq '^u[0-9]+-[a-z0-9-]+$' || die "unit id は u<n>-<slug> 形式: '$id'"
  case "$action" in
    add)   grep -q "^- \[.\] $id " "$dir/state.md" && die "既にあります: $id"
           [ -n "$desc" ] || die "説明が必要です"
           printf -- '- [ ] %s — %s\n' "$id" "$desc" >> "$dir/state.md"; audit UNIT_ADDED "$id" "$dir" ;;
    start) [ "$(field Stage "$dir")" = construction ] || die "unit を始めるには stage construction が必要です(gate plan の承認後)"
           grep -q "^- \[ \] $id " "$dir/state.md" || die "未着手の unit ではありません: $id"
           sed "s|^- \[ \] $id |- [-] $id |" "$dir/state.md" > "$dir/state.md.tmp" && mv "$dir/state.md.tmp" "$dir/state.md"; audit UNIT_STARTED "$id" "$dir" ;;
    done)  grep -q "^- \[-\] $id " "$dir/state.md" || die "進行中の unit ではありません: $id(先に unit start)"
           sed "s|^- \[-\] $id |- [x] $id |" "$dir/state.md" > "$dir/state.md.tmp" && mv "$dir/state.md.tmp" "$dir/state.md"; audit UNIT_DONE "$id" "$dir" ;;
    *) usage ;;
  esac
  echo "unit $action: $id"
}
cmd_note() {
  local heading="${1:-}" text="${2:-}" dir; dir="$(active_dir)" || die "active な intent がありません"
  case "$heading" in Interpretations|Deviations|Tradeoffs|"Open questions") ;; *) die "見出しは Interpretations|Deviations|Tradeoffs|'Open questions'" ;; esac
  [ -n "$text" ] || die "本文が必要です"
  # 見出しの直後(空行の前)ではなく、その節の末尾(次の ## の直前)に追記する。
  awk -v h="## $heading" -v line="- $(now) — $text" '
    { lines[NR]=$0 }
    END {
      ins=0
      for (i=1;i<=NR;i++) if (lines[i]==h) { ins=i; break }
      if (!ins) { for (i=1;i<=NR;i++) print lines[i]; print h; print line; exit }
      end=NR
      for (i=ins+1;i<=NR;i++) if (lines[i] ~ /^## /) { end=i-1; break }
      while (end>ins && lines[end]=="") end--
      for (i=1;i<=NR;i++) { print lines[i]; if (i==end) print line }
    }' "$dir/memory.md" > "$dir/memory.md.tmp" && mv "$dir/memory.md.tmp" "$dir/memory.md"
  audit NOTE "$heading" "$dir"; echo "noted under '$heading'"
}
cmd_close() {
  local dir; dir="$(active_dir)" || die "active な intent がありません"
  if [ "${1:-}" != --abandon ]; then
    grep -q '^- \[[ -]\] ' "$dir/state.md" && die "未完了の unit があります。--abandon で放棄するか、done にしてください"
    [ -f "$dir/retro.md" ] || die "retro.md がありません。/retro を先に(学びをハーネスに戻してから閉じる)"
  fi
  set_field Status "done" "$dir"; audit INTENT_CLOSED "${1:-completed}" "$dir"; echo "closed: $(basename "$dir")"
}
cmd_human_turn() {
  local dir; dir="$(active_dir 2>/dev/null)" || exit 0     # intent が無ければ何もしない(hook から呼ばれる)
  audit HUMAN_TURN "${1:-unknown}" "$dir"
}

# ---- halt-reason(Stop hook が verify を skip してよい理由。ADR-0002)-----------------------------------
HALT_WINDOW_SEC=600   # 提示 / note からこの秒数以内だけ skip できる
HALT_MAX_SKIPS=3      # 窓の中で skip できる回数(note の連発で無期限に延長できない)
cmd_halt_reason() {
  # 出力: gate=intent | gate=plan | open-questions(exit 0)。理由が無い / intent が無い / 上限超過は exit 1。
  local dir; dir="$(active_dir 2>/dev/null)" || exit 1
  local now_e; now_e="$(iso_to_epoch "$(now)")"; [ -n "$now_e" ] || exit 1
  within() { local e; e="$(iso_to_epoch "$1")"; [ -n "$e" ] && [ $((now_e - e)) -le $HALT_WINDOW_SEC ]; }
  local skips=0 ts ev rest
  while IFS="$(printf '\t')" read -r ts ev rest; do [ "$ev" = STOP_SKIP ] && within "$ts" && skips=$((skips+1)); done < "$dir/audit.log"
  [ $skips -ge $HALT_MAX_SKIPS ] && exit 1
  local g; for g in intent plan; do
    if [ "$(field "Gate $g" "$dir")" = presented ]; then
      ts="$(grep "	GATE_PRESENTED	$g\$" "$dir/audit.log" | tail -n1 | cut -f1)"
      [ -n "$ts" ] && within "$ts" && { echo "gate=$g"; exit 0; }
    fi
  done
  ts="$(grep '	NOTE	Open questions$' "$dir/audit.log" | tail -n1 | cut -f1)"
  [ -n "$ts" ] && within "$ts" && { echo open-questions; exit 0; }
  exit 1
}

# ---- event / metrics(ハーネスの判定を記録して数える)-------------------------------------------------
cmd_event() {
  local name="${1:-}" detail="${2:-}" dir
  printf '%s' "$name" | grep -Eq '^[A-Z][A-Z_]+$' || die "event 名は大文字英字と _ のみ: '$name'"
  [ -n "$detail" ] || die "detail が必要です: event $name \"<detail>\""
  detail="$(printf '%s' "$detail" | tr '\t\n' '  ' | cut -c1-120)"
  if dir="$(active_dir 2>/dev/null)"; then audit "$name" "$detail" "$dir"
  else mkdir -p "$(dirname "$METRICS_LOG")" && printf '%s\t%s\t%s\n' "$(now)" "$name" "$detail" >> "$METRICS_LOG"; fi
}
cmd_metrics() {
  local file="" dir
  while [ $# -gt 0 ]; do case "$1" in --file) file="$2"; shift ;; *) die "unknown arg: $1" ;; esac; shift; done
  if [ -z "$file" ]; then
    if dir="$(active_dir 2>/dev/null)"; then file="$dir/audit.log"; else file="$METRICS_LOG"; fi
  fi
  [ -f "$file" ] || die "記録がありません: $file"
  echo "source	$file"
  local e; for e in HOOK_DENY HOOK_ASK STOP_BLOCK POST_EDIT_FAIL HUMAN_TURN GATE_REJECTED; do
    printf '%s\t%s\n' "$e" "$(grep -c "	$e	" "$file" || true)"
  done
  # 経過時間: INTENT_CREATED → INTENT_CLOSED(無ければ現在)。intent 以外の記録なら先頭行 → 末尾行。
  local t0 t1 s0 s1
  t0="$(grep '	INTENT_CREATED	' "$file" | head -n1 | cut -f1)"; [ -n "$t0" ] || t0="$(head -n1 "$file" | cut -f1)"
  t1="$(grep '	INTENT_CLOSED	' "$file" | tail -n1 | cut -f1)"
  if [ -n "$t1" ]; then :; elif grep -q '	INTENT_CREATED	' "$file"; then t1="$(now)"; else t1="$(tail -n1 "$file" | cut -f1)"; fi
  s0="$(iso_to_epoch "$t0")"; s1="$(iso_to_epoch "$t1")"
  if [ -n "$s0" ] && [ -n "$s1" ]; then printf 'elapsed_sec\t%s\n' "$((s1 - s0))"; else echo "elapsed_sec	unknown (date parse failed)"; fi
}

# ---- check(CI)--------------------------------------------------------------------------------
cmd_check() {
  local d rc=0 n=0
  err() { echo "  ✘ $(basename "$d"): $*"; rc=1; }
  for d in "$INTENTS_DIR"/*/; do
    d="${d%/}"; [ -f "$d/state.md" ] || continue; n=$((n+1))
    # 1) state.md の必須フィールド
    local k; for k in Status Scope Stage "Gate intent" "Gate plan"; do [ -n "$(field "$k" "$d")" ] || err "state.md に '$k' がありません"; done
    # 2) intent.md の必須節
    local h; for h in "## 目的" "## スコープ外" "## 受け入れ条件" "## リスクと HITL レベル"; do grep -q "^$h" "$d/intent.md" 2>/dev/null || err "intent.md に '$h' がありません"; done
    # 3) 承認の受領証: GATE_APPROVED の前に GATE_PRESENTED があり、その間に HUMAN_TURN がある
    local g; for g in intent plan; do
      local approved_lines; approved_lines="$(grep -n "	GATE_APPROVED	$g$" "$d/audit.log" 2>/dev/null | cut -d: -f1)"
      local a; for a in $approved_lines; do
        local p; p="$(head -n "$a" "$d/audit.log" | grep -n "	GATE_PRESENTED	$g$" | tail -n1 | cut -d: -f1)"
        [ -n "$p" ] || { err "gate $g: 提示(GATE_PRESENTED)無しに承認されています(audit.log:$a)"; continue; }
        if [ "$(field Receipt "$d")" = consent ]; then
          local last; last="$(sed -n "$((p+1)),$((a-1))p" "$d/audit.log" | grep "	HUMAN_TURN	.* gate=$g\$" | tail -n1 | cut -f3)"
          case "$last" in *"answer=Approve gate=$g") ;; *) err "gate $g: 提示と承認の間に [gate $g] への Approve(AskUserQuestion)がありません(audit.log:${p}-${a}、最新: ${last:-なし})" ;; esac
        else
          sed -n "$((p+1)),$((a-1))p" "$d/audit.log" | grep -q '	HUMAN_TURN	' || err "gate $g: 提示と承認の間に人間の応答(HUMAN_TURN)がありません(audit.log:$p-$a)"
        fi
      done
      # state.md と audit.log の整合
      local st; st="$(field "Gate $g" "$d")"
      local last; last="$(grep "	GATE_\(PRESENTED\|APPROVED\|REJECTED\)	$g" "$d/audit.log" 2>/dev/null | tail -n1 | cut -f2)"
      case "$st" in
        approved*) [ "$last" = GATE_APPROVED ] || err "gate $g: state.md は approved ですが audit.log の最終イベントは ${last:-なし}" ;;
        presented) [ "$last" = GATE_PRESENTED ] || err "gate $g: state.md は presented ですが audit.log の最終イベントは ${last:-なし}" ;;
      esac
    done
    # 4) 段階と承認の順序
    case "$(field Stage "$d")" in
      inception|construction|handoff|operation) [[ "$(field 'Gate intent' "$d")" == approved* ]] || err "stage が $(field Stage "$d") なのに gate intent が未承認" ;;
    esac
    case "$(field Stage "$d")" in
      construction|handoff|operation)
        [[ "$(field 'Gate plan' "$d")" == approved* ]] || err "stage が $(field Stage "$d") なのに gate plan が未承認"
        for h in "## 分解" "## 順序と walking skeleton" "## Definition of Done"; do grep -q "^$h" "$d/plan.md" 2>/dev/null || err "plan.md に '$h' がありません"; done ;;
    esac
    # 5) plan.md の units ブロック: 宣言済みの unit にだけ依存し、循環が無い(Kahn)
    if [ -f "$d/plan.md" ] && grep -q '^units:' "$d/plan.md"; then
      local out; out="$(awk '
        /^```yaml/ {inb=1; next} /^```/ {inb=0}
        inb && /^units:/ {inu=1; next}
        inu && /^  - name:/ { n=$3; names[n]=1; order[++cnt]=n; cur=n; next }
        inu && /^    depends_on:/ { s=$0; sub(/.*\[/,"",s); sub(/\].*/,"",s); gsub(/[ ,]+/," ",s); deps[cur]=s; next }
        inu && /^[^ ]/ { inu=0 }
        END {
          for (i=1;i<=cnt;i++) { u=order[i]; m=split(deps[u],arr," "); for (j=1;j<=m;j++) { v=arr[j]; if (v=="") continue; if (!(v in names)) print "undeclared: " u " -> " v; if (v==u) print "self: " u; indeg[u]++; adj[v]=adj[v] " " u } }
          # Kahn
          removed=0
          do { progress=0; for (i=1;i<=cnt;i++) { u=order[i]; if (!(u in gone) && indeg[u]+0==0) { gone[u]=1; removed++; progress=1; m=split(adj[u],arr," "); for (j=1;j<=m;j++) if (arr[j]!="") indeg[arr[j]]-- } } } while (progress)
          if (removed<cnt) print "cycle among units"
        }' "$d/plan.md")"
      [ -z "$out" ] || err "plan.md units: $out"
    fi
  done
  echo "  checked $n intent(s)"
  return $rc
}

cmd="${1:-}"; shift || true
case "$cmd" in
  new) cmd_new "$@" ;;
  active) active_dir ;;
  status) cmd_status ;;
  gate) cmd_gate "$@" ;;
  stage) cmd_stage "$@" ;;
  unit) cmd_unit "$@" ;;
  note) cmd_note "$@" ;;
  close) cmd_close "$@" ;;
  human-turn) cmd_human_turn "$@" ;;
  event) cmd_event "$@" ;;
  halt-reason) cmd_halt_reason ;;
  metrics) cmd_metrics "$@" ;;
  check) cmd_check ;;
  *) usage ;;
esac
