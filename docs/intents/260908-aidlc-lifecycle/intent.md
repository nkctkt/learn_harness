# 260908-aidlc-lifecycle

- Scope: harness
- 作成: 2026-09-08

## 目的

ハーネスが覆っていない上流(意図・計画・承認)と下流(リリース・障害・振り返り)の各タスクに、AWS の AI-DLC(`../aidlc-workflows`)を参照した
記録・ゲート・手順を追加し、「Agent が勝手に決めて勝手に作る」「人間不在で自己承認する」「セッションを跨いで文脈を失う」を止められるようにする。
エンジンは借りず、既存の bash hook / verify / CI の流儀で最小に再実装する(ADR-0001)。

## スコープ外

- AI-DLC の 33 ステージ・11 scope・swarm / worktree / 自律モードの再現。
- 複数 intent の並行(active は 1 つ)。
- sandbox の有効化、harden-runner の block 化(Exercise 11 の残課題のまま)。
- アプリ(Reading Shelf)の機能変更。

## 受け入れ条件

- [x] AC1: 計画未承認のあいだ `apps/ services/ packages/ infra/ contracts/` への Edit / Write が deny される(`scripts/tests/hooks.test.sh`)
- [x] AC2: ゲート提示後に人間の応答(HUMAN_TURN、hook が記録)が無い `gate approve` は拒否される(`scripts/tests/intent.test.sh`)
- [x] AC3: 改竄された記録(HUMAN_TURN 削除、state と audit の不一致、unit の循環、未宣言 unit への依存、必須節の欠落の 5 種)を `intent.sh check` が落とし、CI(`--only docs`)で走る
- [x] AC4: SessionStart で active intent の状態と hook の健全性が additionalContext として注入される(`hooks.test.sh`)
- [x] AC5: ライフサイクルの各タスクに skill がある(intent / plan-units / adr / build-unit / create-pr / release / incident / retro)。`.claude/rules/` が領域別に存在する
- [x] AC6: この intent 自身がゲートを通る(人間が `gate approve intent` / `gate approve plan` を行い、CI の check が通る)。事後に intent を作るのはこの Phase のブートストラップだけで、次の intent からは作業前に作る(`docs/lifecycle.md` §3)

## リスクと HITL レベル

- 触れる信頼境界: ハーネス自体(`.claude/settings.json`、hooks、`.github/workflows/security.yml`、`scripts/verify.sh`)
- HITL: 4(CODEOWNERS 承認。workflow / settings / hooks の変更理由を PR に書く)
- 想定されるリスク:
  - 新しい PreToolUse hook(guard-plan-approval)の構文エラーで Edit / Write が全滅する → `bash -n`(pre-commit、SessionStart の健全性チェック)、ERR trap で deny
  - UserPromptSubmit hook が毎ターン走る → 数十 ms、intent が無ければ即 exit 0
  - guard-bash の新パターンが誤検知する(`docs/intents` を含む正当なコマンド)→ 書込系の語と同時一致に限定。テストケースはファイルに置く
