# ADR-0001: ライフサイクルの記録と承認ゲートを bash + markdown で再実装する(AI-DLC のエンジンを採用しない)

- Status: Proposed(gate plan の承認で Accepted)
- Date: 2026-09-08
- Intent: docs/intents/260908-aidlc-lifecycle

## Context

ハーネスは Construction → CI の区間しか覆っておらず、意図・計画・承認・振り返りの記録が無い。
AWS の AI-DLC(`../aidlc-workflows`)は同じ問題を、TypeScript のオーケストレーションエンジン(約 50 tools、17 hooks、
状態機械と runtime-graph)と 33 ステージで解いている。本リポジトリは学習が目的で、単独メンテナ、bash 3.2 の hook、
jq 以外の依存を持たない方針(`.claude/hooks/*`)で来ている。学ぶべきは「受領証を誰が発行し、ゲートを誰が開けるか」であり、
エンジンの実装ではない。

## Decision

記録を `docs/intents/<id>/`(markdown + TSV の監査ログ)に置き、状態遷移と承認ゲートを `scripts/intent.sh`(bash、依存なし)
で扱う。人間の在席の受領証(HUMAN_TURN)は Claude Code の hook(UserPromptSubmit / AskUserQuestion)だけが書く。
AI-DLC からは仕組み(record dir、HARD STOP、plan-approval guard、SessionStart の再注入、memory の層、Learnings Ritual)を借り、
エンジン・scope グリッド・swarm・sensor 機構は採用しない。

## Consequences

- 良: 依存ゼロで読める(intent.sh は 300 行弱)。既存の hook / verify / CI にそのまま乗る。学習者が全行を追える。
- 良: 記録が Git に入り、PR でレビューされ、CI(`docs` 段)が整合性を検査する。
- 悪: AI-DLC の 33 ステージ・複数 intent の並行・自律モードは無い。unit の並行実行(worktree)も無い。
- 悪: 受領証はローカル層なので改竄できる(全ローカル層と同じ)。露見させるのは CI と PR レビュー。
- 次の判断: intent を必須にするか(`HARNESS_REQUIRE_INTENT=1`)。複数 intent を並行させたくなった時の設計。

## Alternatives

- AI-DLC をそのまま導入(`dist/claude/`): 完成度は高いが、Bun 依存と ~50 tools がブラックボックスになり、学習目的に合わない。既存の verify / hooks と二重化する。
- Claude Code の Task / TodoWrite だけで状態管理: セッションを跨がず、承認の受領証が無い。
- GitHub Issues / Projects を状態にする: 承認は PR レビューで代替できるが、「コードを書く前の承認」(plan gate)がローカルで強制できない。
