---
name: plan-units
description: 承認済みの intent を、依存関係付きの unit(独立に実装・検証できる単位)に分解し、walking skeleton を先頭にした順序と unit ごとの Definition of Done を plan.md に書く。plan-reviewer subagent の指摘を反映してから人間の承認ゲート(gate plan)に出す。AI-DLC の Inception(domain-design / units-generation / delivery-planning)に相当。
argument-hint: ""
---

# /plan-units — 分解・順序・完了条件を、コードより先に決める

前提: `scripts/intent.sh status` が `stage=inception`、`gate intent=approved`。
この skill が終わるまで `apps/ services/ infra/` は書けない(guard-plan-approval)。**計画は入力であって出力ではない。**

## 手順

1. **読む**: `intent.md`、AGENTS.md、触る領域の `.claude/rules/*.md`、関連する既存コードとテスト、`contracts/`。
2. **元に戻しにくい判断があれば先に `/adr`**(DB スキーマ、API 契約、新しい依存・言語、サービス境界)。plan.md から ADR 番号で参照する。
3. **`docs/intents/<id>/plan.md` を書く**(見出しは固定。CI が検査する)

   ```markdown
   # plan — <id>

   ## 設計判断
   - ADR-000N: ...(無ければ「なし」)

   ## 分解(Units)
   ```yaml
   units:
     - name: u1-skeleton        # u<n>-<slug>。小文字英数字とハイフン
       kind: service            # service | spec | ui | packaging | library
       depends_on: []
     - name: u2-...
       depends_on: [u1-skeleton]
   ```
   | Unit | 触るパス | 触れる境界 | 大きさ |
   |---|---|---|---|
   | u1-skeleton | apps/api/src/links/... | SQL | S |

   ## 順序と walking skeleton
   u1 は全ての結合点(web → api → DB → enricher / shortener)を通る最薄の縦串。動くまで u2 以降に進まない。
   順序の根拠(リスク先行 / 価値先行 / 依存順)を 1〜2 行。

   ## Definition of Done
   - u1: `routes.test.ts` の「...」が通る、`INTEGRATION=1` で `repository.integration.test.ts` が通る、compose で `POST /links` → 201
   - u2: ...

   ## 検証計画
   | AC | Unit | テスト / verify の段 |
   |---|---|---|

   ## ハーネスへの影響
   - 触るゲート(hook / verify / CI / policy)と理由。無ければ「なし」。あれば HITL-4。
   ```

   - unit は 1〜7 個。8 個以上なら intent を分ける。各 unit は 1 コミットか数コミットで閉じる大きさ。
   - `depends_on` は宣言済みの unit だけ、循環なし(CI の `intent.sh check` が落とす)。
   - DoD は **テスト名か verify の段で言う**。「動く」「壊れない」は DoD ではない。
   - 全ての AC がどこかの unit に載っていること(載らない AC はスコープ外へ移すか、unit を足す)。
4. **unit を登録する**(state.md のチェックボックスになる)
   ```
   scripts/intent.sh unit add u1-skeleton "縦串: POST /links → DB → short"
   ```
5. **plan-reviewer に読ませる**(Agent tool で `plan-reviewer` subagent)。NOT-READY の指摘は直す。直さない判断は `scripts/intent.sh note Deviations "..."` に理由を残す。reviewer は助言でありゲートではない。
6. **ゲートに出す**: `scripts/intent.sh gate present plan`。見せるのは plan.md のパス、unit 表と DoD、承認後に `/build-unit u1-...` から始めること。
   **AskUserQuestion** で聞く。質問文の先頭に `[gate plan]`、選択肢は **Approve / Request Changes の 2 つだけ**。ここで人間の回答を待つ。テキストの返答は承認にならない。
7. **回答が返った同じターンで**: Approve → `gate approve plan` → `stage construction` → `/build-unit <u1>`。Request Changes → `gate reject plan "<理由>"` → 直して 6 へ(再提示)。

## 承認後に計画を変えたくなったら(halt-and-ask)

実装中に DoD が満たせない・unit の境界が違ったと分かったら、勝手に直さない。`note "Open questions"` に書き、ターンを終えて人間に聞く。
計画の実質が変わるなら `gate reject plan "<変更点>"` → 直して再提示(承認は取り直す)。
