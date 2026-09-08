---
name: retro
description: intent を閉じる前に memory.md と audit.log から学びを取り出し、AGENTS.md / .claude/rules / skill / hook・verify(決定論的検査)/ docs/exercises のどこに書き戻すかを決めて実際に書き、retro.md に残して close する。AI-DLC の Learnings Ritual(§13)と feedback-optimization に相当。学びをチャットに残さない。
argument-hint: ""
---

# /retro — 学びを「次の Agent が自動で読む場所」に書き戻す

AI-DLC の原則: **stage(手順)は不変、harness は可変。** 学びは会話ではなく、rules / hook / verify / skill に入れて初めて次回に効く。
`docs/exercises/` はこれを手作業でやってきた。/retro はそれを毎 intent の儀式にする。

前提: PR が merge 済み(`stage=handoff` か `operation`)。`retro.md` が無いと `intent.sh close` は拒否する。

## 手順

1. **材料を読む**
   - `memory.md`(Interpretations / Deviations / Tradeoffs / Open questions)
   - `scripts/intent.sh metrics`: ハーネスが Agent を止めた回数(`HOOK_DENY` / `HOOK_ASK` / `STOP_BLOCK` / `POST_EDIT_FAIL`)、Stop hook を skip した回数(`STOP_SKIP`、理由別 `gate` / `open-questions`。ADR-0002。unit 数を超えていたら窓と上限を狭める候補)、`HUMAN_TURN`(人間の手間)、`GATE_REJECTED`(計画の精度)、`elapsed_sec`(作成 → close)。
     deny / ask の内訳は `grep HOOK_ audit.log` で hook 名と理由を読む。**誤検知(止める必要が無かった deny)は行き先「hook / verify」の候補**
   - `audit.log`: `GATE_REJECTED` の理由、unit の start → done の間隔
   - PR のレビューコメント(`gh pr view <n> --comments`)と、`/fix-ci` を使ったなら CI の失敗
2. **学びを 1 行ずつ列挙し、行き先を決める**(判断基準は「次の Agent がそれを自動で読むか、機械が強制するか」)

   | 学びの種類 | 行き先 | 例 |
   |---|---|---|
   | 事実・短い規約(領域固有) | `.claude/rules/<area>.md` | 「契約の変更は api 側から始める」 |
   | 事実・短い規約(全体) | `AGENTS.md`(200 行以内。手順は書かない) | 「`$a。` は bash 3.2 で壊れる」→ rules/harness.md の方が適切 |
   | 手順 | 既存 skill の追記 / 新 skill | `/fix-ci` の「よくある原因」表 |
   | 機械で強制できる | hook / `verify.sh` の段 / Semgrep / Rego(**最優先**) | 「フィールド名変更で契約が壊れた」→ 契約テスト |
   | 意図的欠陥で検証した | `docs/exercises/NN-*.md` | Phase の記録 |
   | 判断(戻しにくい) | `/adr` | |
   | 何もしない | retro.md に理由 | 1 回きりの事象 |

   迷ったら **決定論的な方へ**。指示(rules)は request に過ぎず、hook / CI だけが強制できる(plan §6)。
3. **書き戻す**。ハーネス(`.claude/**` `scripts/**` `policies/**` `.github/**`)の変更は guard-edit が ask にする(HITL-4)。変更したら `scripts/verify.sh --only docs`(hook テスト)と `bash -n`。テンプレート(`templates/harness/template/`)にも同期する。
4. **`docs/intents/<id>/retro.md` を書く**
   ```markdown
   # retro — <id>
   ## 何が起きたか(3〜5 行)
   ## 学びと行き先
   | 学び | 行き先 | 変更(パス) |
   ## 計測(`scripts/intent.sh metrics` の出力を貼る)
   deny: N 回(うち誤検知 N)/ ask: N 回 / Stop block: N 回 / Stop skip: N 回(gate N、open-questions N)/ post-edit 失敗: N 回 / HUMAN_TURN: N 回 / gate reject: N 回 / 経過: N 分
   unit 数: N / CI 失敗: N 回
   ## 次の intent への申し送り(Open questions の残り)
   ```
   incident なら `/incident` のポストモーテム表をここに含める。
5. **閉じる**: `scripts/intent.sh close`(未完了 unit があれば `--abandon` と理由)。

## やらないこと

- 学びを AGENTS.md に長文で書く(200 行制限。手順は skill、領域は rules)。
- 「気をつける」で終える(誰も気をつけない。検査にするか、しない理由を書く)。
- retro を飛ばして close する(`intent.sh` が拒否する)。
