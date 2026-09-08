---
name: intent
description: 変更 1 件の記録(docs/intents/<id>/)を作り、目的・スコープ外・受け入れ条件・HITL レベルを intent.md に書いて、人間の承認ゲート(gate intent)に出す。AI-DLC の Ideation(intent-capture / scope-definition)に相当。アプリの振る舞いを変える作業はここから始める。
argument-hint: "<slug> [--scope feature|bugfix|refactor|harness]"
---

# /intent — 何を・なぜ・どこまでを、コードより先に決める

「Agent が勝手に決めて勝手に作る」を止める最初のゲート。計画(`/plan-units`)より前、コードより前。
小さな修正(typo、依存更新、docs)には要らない。`apps/ services/ infra/` の振る舞いを変えるなら作る。

## 手順

1. **記録を作る**
   ```
   scripts/intent.sh new <slug> --scope <feature|bugfix|refactor|harness>
   ```
   active な intent は 1 つだけ。既にあれば先に `/retro` → `close`。
2. **`intent.md` を埋める**(生成された 4 節を全て。CI の `intent.sh check` が節の欠落を落とす)
   - **目的**: 何を、誰のために、なぜ。1 段落。「〜できるようにする」で終わる文。
   - **スコープ外**: 今回やらないことを列挙。後で「ついで」に膨らむ経路を先に塞ぐ。
   - **受け入れ条件**: 検証可能な文(`AC1: POST /links が 201 と short を返す(routes.test.ts)`)。各 AC は後で unit と テストに対応づける。「動く」「良くなる」は AC ではない。
   - **リスクと HITL レベル**: 触れる信頼境界(認証 / SQL / 外部 fetch / infra / ハーネス自体)。`.github .claude policies infra` と依存追加は HITL-4(CODEOWNERS 承認)。`--scope harness` は常に 4。
   - scope が `bugfix` なら **再現手順と、落ちるべきテスト名** を目的に含める(`/incident` 参照)。
3. **曖昧なら聞く**(AskUserQuestion、最大 3 問)。「推奨で進めて」は今回だけの指示で、恒久ルールではない。
4. **ゲートに出す**
   ```
   scripts/intent.sh gate present intent
   ```
   人間に見せるのは 3 つ: 作ったもの(`docs/intents/<id>/intent.md`)、特に見てほしい所(スコープ外と HITL)、承認後に起きること(`/plan-units` で分解と計画)。
   選択肢は **Approve / Request Changes の 2 つ**。**ここでターンを終える。** 同じターンで approve しない(hook が記録する人間の応答が無いと `intent.sh` が拒否する)。
5. **人間の応答後**
   - Approve → `scripts/intent.sh gate approve intent` → `scripts/intent.sh stage inception` → `/plan-units`
   - Request Changes → `scripts/intent.sh gate reject intent "<理由>"` → 直して 4 へ

## やらないこと

- 承認前に `apps/ services/ packages/ infra/ contracts/` を書く(guard-plan-approval が deny する。計画承認まで続く)。
- `state.md` / `audit.log` を直接編集する。
- 受け入れ条件を実装後に書き足す(計画が「出力」になる)。
