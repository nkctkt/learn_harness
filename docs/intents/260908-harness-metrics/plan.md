# plan — 260908-harness-metrics

## 設計判断

- ADR: なし(元に戻しにくい判断は無い。イベント名と TSV 形式は既存 `audit.log` の流儀に従う)
- 記録の入口は 1 つ: `scripts/intent.sh event <EVENT> "<detail>"`(hook 専用。`human-turn` と同じ扱い)。
  active な intent があれば `audit.log`、無ければ `$ROOT/.claude/metrics.log`(gitignore)に同じ TSV(ts / event / detail)で追記する。
  hook は `intent.sh event ... >/dev/null 2>&1 || true` を **判定 JSON を出す直前** に呼ぶ(記録の失敗は判定に影響しない)。
  呼び出しは各分岐に置かず、各 hook の `deny()` / `ask()` / `decide()` / `block()` ヘルパーの中に **1 回だけ** 入れる(guard-bash は 8 分岐あるが挿入は 2 箇所)。
  これらのヘルパーは `exit 0` で終わるので「判定の後」に置くとデッドコードになる。
- `.claude/metrics.log` は intent 外の摩擦を見るための **ローカル専用** の記録(Git 追跡外、`intent.sh check` の対象外)。
  Phase 9 の「記録は Git に入れて CI で露見させる」の外にある非対称は意図的: intent 外の作業に受領証は無く、改竄を防ぐ動機も無い。
  `intent.sh metrics` は active intent があれば `audit.log`、無ければ `.claude/metrics.log` を読む(`--file <path>` で明示も可)。
- 経過時間の計算(AC4)は ISO-8601 → epoch の変換が要る。`iso_to_epoch()` を intent.sh に足し、GNU `date -u -d "$1" +%s` を試して失敗したら BSD `date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$1" +%s` に落とす(macOS ローカルと ubuntu の CI の両方で通す)。
- イベント名: `HOOK_DENY` / `HOOK_ASK`(detail = `<hook>: <理由の先頭 80 字>`)、`STOP_BLOCK`(detail = 失敗した段)、`POST_EDIT_FAIL`(detail = ファイル)。
  guard-secrets は exit 2 で block するので `HOOK_DENY guard-secrets` として記録する。allow は記録しない(ノイズ)。
- `intent.sh check` は既知イベントを grep するだけなので新イベントで落ちない。ただし AC5 として明示的にテストする。
- guard-bash §6 の ask 対象に `intent\.sh[[:space:]]+event` を加える(Agent が Bash から捏造する経路を human-turn と同じ扱いにする)。

## 分解(Units)

```yaml
units:
  - name: u1-event-sink
    kind: library
    depends_on: []
  - name: u2-hook-wiring
    kind: service
    depends_on: [u1-event-sink]
  - name: u3-retro-and-templates
    kind: packaging
    depends_on: [u2-hook-wiring]
```

| Unit | 触るパス | 触れる境界 | 大きさ |
|---|---|---|---|
| u1-event-sink | `scripts/intent.sh`(`event` / `metrics` サブコマンド、`iso_to_epoch`)、`.gitignore`、`scripts/tests/intent.test.sh` | ハーネス(記録の正規入口) | S |
| u2-hook-wiring | `.claude/hooks/{guard-bash,guard-edit,guard-plan-approval,guard-secrets,stop-verify,post-edit-check}.sh`、`scripts/tests/hooks.test.sh` | ハーネス(hook。fail-closed を壊さないこと) | M |
| u3-retro-and-templates | `.claude/skills/retro/SKILL.md`、`scripts/tests/harness-shape.test.sh`、`templates/harness/template/**`(同期) | ハーネス(テンプレート) | S |

## 順序と walking skeleton

u1 が縦串: 「hook → `intent.sh event` → audit.log / metrics.log → `intent.sh metrics` が数える」の経路を、hook を触らずに(テストから `event` を直接呼んで)先に通す。
理由: 6 本の hook を触る u2 は fail-closed を壊すリスクが最も高いので、記録先と集計を固めてから 1 行ずつ足す(リスク先行)。u3 は u2 の結果(イベント名)が確定してから。

## Definition of Done

- u1: `intent.test.sh` に次が通る
  - 「event は active intent の audit.log に TSV で追記する」
  - 「event は intent が無ければ .claude/metrics.log に追記する」
  - 「metrics が HOOK_DENY / HOOK_ASK / STOP_BLOCK / POST_EDIT_FAIL / HUMAN_TURN / GATE_REJECTED の回数と経過時間を出す」
  - 「新イベントを含む audit.log を check が通す」(AC5)
  - 「metrics は intent が無ければ .claude/metrics.log を読む」
  - 「.gitignore に .claude/metrics.log がある」(u1 で `.gitignore` を変更し、`intent.test.sh` の grep で検査)
  - 「iso_to_epoch が 2026-09-08T00:00:00Z と 2026-09-08T01:30:00Z の差を 5400 と返す」(macOS ローカルで通し、CI の docs 段(ubuntu)でも同じテストが走る)
- u2: `hooks.test.sh` に次が通る
  - guard-plan-approval / guard-edit / guard-bash の deny と ask がそれぞれ `HOOK_DENY` / `HOOK_ASK` を audit.log に書く(AC1)
  - guard-secrets の block が `HOOK_DENY guard-secrets` を書く(AC1)
  - stop-verify の exit 2 が `STOP_BLOCK`、post-edit-check の失敗が `POST_EDIT_FAIL` を書く(AC2)
  - intent 無しの deny が `.claude/metrics.log` に書かれる(AC3)
  - `INTENTS_DIR` を書込不可にしても判定(deny / ask / exit 2)が変わらない(AC6)
  - `scripts/intent.sh event X` を Bash から呼ぶと guard-bash が ask にする
  - 既存 assertion が全て通る(判定条件は不変)
- u3:
  - `harness-shape.test.sh` に「retro skill の計測欄に `deny` `Stop block` `metrics` の語がある」が通る(AC7)
  - `harness-shape.test.sh` の template drift 検査が通る(hooks / intent.sh / tests / retro skill を同期)(AC7)
  - `scripts/verify.sh --only docs` が全体で通る

## 検証計画

| AC | Unit | テスト / verify の段 |
|---|---|---|
| AC1 | u2 | `hooks.test.sh`(docs 段) |
| AC2 | u2 | `hooks.test.sh` |
| AC3 | u1, u2 | `intent.test.sh`(metrics.log への追記、gitignore の grep)、`hooks.test.sh`(hook 経由) |
| AC4 | u1 | `intent.test.sh` |
| AC5 | u1 | `intent.test.sh` |
| AC6 | u2 | `hooks.test.sh` |
| AC7 | u3 | `harness-shape.test.sh`(drift + retro の項目) |

## ハーネスへの影響

- hook 6 本、`scripts/intent.sh`、`scripts/tests/*`、retro skill、`.gitignore`、templates を触る。HITL-4(CODEOWNERS)。
- hook の **判定条件は変えない**。追加するのは判定直前の記録 1 行のみ。全 hook は編集後に `bash -n`(lefthook が強制)。
- CI: 変更なし(docs 段が既に `scripts/tests/*.test.sh` を回す)。
- `audit.log` に hook 判定が混ざるため、`intent.sh check` の受領証検査(GATE_PRESENTED → HUMAN_TURN → GATE_APPROVED の順序)が新イベントを誤読しないことを AC5 で担保する。
