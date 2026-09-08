# ADR-0002: Stop hook に「人間に相談するためにターンを終える」例外を設ける

- Status: Accepted(2026-09-08、gate plan)
- Date: 2026-09-08
- Intent: docs/intents/260908-stop-hook-halt

## Context

Stop hook(`stop-verify.sh`)は「Agent がテストしたと言う」を「テストが実際に通った」に置き換える、ハーネスで最も荷重の掛かる fail-safe。
一方でライフサイクル(Phase 9)は、計画から外れた時とゲートを提示した時に「ターンを終えて人間を待て」と要求する。
落ちたテストを抱えたまま人間に相談する経路は設計上は正しいのに、Stop hook がそれを機械的に塞いでいる(`docs/improvement-plan.md` H4)。

## Decision

Stop hook は次の 2 条件のどちらかが **600 秒以内** に起きていれば verify を skip し、`STOP_SKIP <理由>` を audit.log に記録する:
(1) ゲートを提示した(`GATE_PRESENTED`)、(2) `NOTE Open questions` を残した。
判定は `scripts/intent.sh halt-reason` に置き、hook は結果を適用するだけ。600 秒の窓の中で skip は最大 3 回(`STOP_SKIP` の件数で数える)。
それ以外は従来どおり block する。intent.sh が壊れていれば skip しない(block 側に倒す)。
`metrics` は `STOP_SKIP` を理由別に数え、`/retro` の計測欄に載せる。

## Consequences

- 良: halt-and-ask とゲート提示が、Stop hook と矛盾しなくなる。相談の経路が機械的に開く。
- 良: 回避は必ず記録される。回数が増えれば retro で見え、窓と上限を狭める根拠になる。
- 悪: Agent が `note "Open questions"` を書くだけで最大 3 回 / 10 分の回避ができる。CI(全体 verify、Rulesets)が最終防衛線であることは変わらないが、ローカルの fail-safe は弱まる。
- 悪: 前例になる。次に Stop hook を緩めたい時は、この ADR を更新してから。
- 次の判断: 常態化(1 intent で STOP_SKIP が unit 数を超える等)が観測されたら、窓を狭めるか「skip の次のターンは必ず verify」を足す。

## Alternatives

- Stop hook を変えず、halt-and-ask を AskUserQuestion(同一ターン)だけで行う: 人間が「計画を変える」と答えた後もテストは落ちたままで、結局ターンを終えられない。
- 環境変数で Stop hook を無効化できるようにする: 記録が残らず、回避が常態化しても気づけない。却下。
- verify の失敗を「警告」に格下げする: 「テストした」が「テストが通った」に戻らない。却下。
