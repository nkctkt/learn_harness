# 260908-consent-receipt

- Scope: harness
- 作成: 2026-09-08
- 出典: `docs/improvement-plan.md` H2(承認の受領証が「在席」であって「同意」ではない)

## 目的

承認ゲート(intent / plan)の受領証を「人間が何か入力した」(HUMAN_TURN)から「人間が Approve を選んだ」に変える。
今は `gate approve` の前に任意のプロンプトがあれば承認でき、人間の文章を Approve と解釈するのは Agent 自身で、「続けて」でも承認が通る。
hook が AskUserQuestion の回答(選択肢のラベル)を受領証に書き、`intent.sh gate approve` と CI の `check` はその回答が Approve の時だけ承認を認めるようにする。
「同意」を Agent の解釈ではなくハーネスの事実にする。

## スコープ外

- 改善計画の他項目(H4 Stop hook の skip、M7 記録の cwd / agent 区別、M 系)。別 intent
- 既存の記録(`docs/intents/260908-aidlc-lifecycle`、`260908-harness-metrics`)の移行。旧形式のまま従来の検査で通す(後方互換)
- ゲートの選択肢を増やすこと(2 択のまま。AI-DLC の NO EMERGENT BEHAVIOR)
- AskUserQuestion の「Other」(自由記述)を承認として扱うこと。自由記述は Request Changes と同じ扱い(承認したいなら Approve を選び直す)
- UserPromptSubmit 由来の HUMAN_TURN の記録をやめること(在席の記録としては残す。承認の受領証に使えなくなるだけ)

## 受け入れ条件

- [ ] AC1: `record-human-turn.sh` が PostToolUse:AskUserQuestion の `tool_response` から選択されたラベルを取り出し、質問文に `[gate <g>]` の印がある時だけ `HUMAN_TURN` の detail を `PostToolUse:AskUserQuestion answer=<label> gate=<g>` として記録する。ラベルが取れない(自由記述・形式不明)時や印が無い時は `answer=` を付けない(`scripts/tests/hooks.test.sh`)
- [ ] AC2: 新形式の intent(state.md に `Receipt: consent`)では、`gate approve <g>` は提示より後の `gate=<g>` 付き HUMAN_TURN のうち最新が `answer=Approve` の時だけ通る。`gate=` 無しの HUMAN_TURN(UserPromptSubmit 等)は無視する。UserPromptSubmit だけ、`answer=Request Changes`、別ゲートの Approve は拒否し、理由に「AskUserQuestion([gate <g>])で Approve を」と出す(`scripts/tests/intent.test.sh`)
- [ ] AC3: `intent.sh new` が作る state.md に `- Receipt: consent` が入る。旧記録(フィールド無し)は `gate approve` も `check` も従来の規則(提示後に HUMAN_TURN があればよい)のまま通る(`intent.test.sh`、既存 2 intent に対する `intent.sh check`)
- [ ] AC4: `intent.sh check` は `Receipt: consent` の intent について、各 GATE_APPROVED より前(提示より後)の最新の `gate=<g>` 付き HUMAN_TURN が `answer=Approve` であることを検査し、UserPromptSubmit だけで承認された改竄を落とす(`intent.test.sh`)
- [ ] AC5: `/intent` と `/plan-units` のゲート提示手順が「質問文に `[gate <g>]` を含む AskUserQuestion で Approve / Request Changes の 2 択を出し、回答が返った同じターンで `gate approve` / `gate reject` を呼ぶ」に変わり、`harness-shape.test.sh` が両 skill にその記述(`AskUserQuestion`、`[gate`)があることを検査する
- [ ] AC6: `.claude/rules/intents.md` と `docs/lifecycle.md` §1 / §4 の受領証の説明が新形式に更新され、templates が同期されている(`harness-shape.test.sh` の drift 検査)

## リスクと HITL レベル

- 触れる信頼境界: ハーネス自体(`record-human-turn.sh`、`scripts/intent.sh`、`scripts/tests/*`、skill 2 本、rules、templates)
- HITL: 4(scope=harness)
- 想定されるリスク:
  - AskUserQuestion の `tool_response` の形(回答がどのキーに入るか)を実機で確認していない → u1 の最初の作業で hook 入力を一度ダンプして形を確定し、memory.md に残す。形が取れない環境では `answer=` 無しになり承認できない(fail-closed)
  - AskUserQuestion を出さずにテキストでゲートを提示した場合、人間が「Approve」と打っても承認できなくなる → skill と rules で AskUserQuestion を必須にし、`gate approve` の拒否理由でも案内する
  - 旧記録との互換: `Receipt` フィールドの有無で規則を切り替えるため、旧 intent には影響しない。ただし新 intent の state.md を手で旧形式に戻せば規則を緩められる → state.md への直接書込は guard-edit が deny、CI の check で `Receipt` 無しの新規 intent(作成日がこの変更以後)を落とすかは plan で決める
  - 承認の人間の手間: ゲートごとに AskUserQuestion が 1 回増える(今は自由記述)。回数は `intent.sh metrics` の HUMAN_TURN で見える
