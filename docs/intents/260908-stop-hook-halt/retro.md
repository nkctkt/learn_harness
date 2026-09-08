# retro — 260908-stop-hook-halt

## 何が起きたか

改善計画 H4(Stop hook と halt-and-ask の衝突)を一周した(PR #27)。`Receipt: consent` で作られた最初の intent で、両ゲートとも `[gate <g>]` 付き AskUserQuestion の Approve で承認された。
plan-reviewer は NOT-READY 2 件(gate 提示中の skip に窓が無い、note の連発で無期限に延長できる)を返し、窓 600 秒 + 上限 3 回 + 理由別 metrics を設計に入れ、ADR-0002 を書いた。
test-reviewer に時間予算 15 分・mutation 6 件を指示したところ 19 分で完了し(前回 56 分)、7 mutation 中 6 件を捕捉、素通り 1 件(exit code だけ壊す)をテストに変換した。
hooks.test.sh が本物の `.claude/metrics.log` に deny を 23 件書き込んでいた(テストの汚染)。retro でテストを直し、ログを空にした。
audit.log を読む grep に `2>&1` を付けただけで guard-bash §6 が ask になっていた(誤検知)。hook を直した。

## 学びと行き先

| 学び | 行き先 | 変更(パス) |
|---|---|---|
| reviewer に時間予算と mutation 上限を書くと、捕捉率を落とさずに 56 分 → 19 分 | agent 定義(次の subagent が自動で読む)。improvement-plan M8 は済 | `.claude/agents/test-reviewer.md`「時間予算」節 |
| テストが `HARNESS_METRICS_LOG` を export する前に hook を呼び、本物の metrics.log を汚していた | テスト(決定論的) | `scripts/tests/{hooks,intent}.test.sh` の先頭で export |
| `2>&1` は書込ではないのに §6 の `>` に一致していた | hook(判定条件の誤検知修正)+ テスト | `.claude/hooks/guard-bash.sh` §6、`hooks.test.sh` に allow / ask の 2 assertion |
| Stop hook を緩める判断は ADR に残す(前例になる) | ADR | `docs/adr/0002-stop-hook-consultation-exception.md` |
| hook が書く audit.log の差分で `git checkout` が止まった(2 回目) | improvement-plan M6 の実測。rules には書いてあり、自分が忘れた | `docs/improvement-plan.md` |
| DoD のテスト(docs 段の `*.test.sh`)は `verify.sh --changed` では走らない。unit の検証は直接叩く | plan に明記(plan-reviewer の提案)。次は build-unit skill に書くべきか検討 | `plan.md` |

## 計測(`scripts/intent.sh metrics` の出力)

```
HOOK_DENY	0
HOOK_ASK	11
STOP_BLOCK	0
STOP_SKIP	0
POST_EDIT_FAIL	0
HUMAN_TURN	6
GATE_REJECTED	0
STOP_SKIP:gate	0
STOP_SKIP:open-questions	0
elapsed_sec	17042
```

deny: 0 回 / ask: 11 回(hook 編集 1、docs / テンプレートを触る python3 heredoc と cp 8、audit.log を読む grep の `2>&1` 2 = 誤検知 2、修正済み)/ Stop block: 0 / Stop skip: 0(gate 0、open-questions 0)/ post-edit 失敗: 0 / HUMAN_TURN: 6(うち AskUserQuestion 3)/ gate reject: 0 / 経過: 284 分(作成 → close 直前。merge 待ちを含む。作業は約 70 分)
unit 数: 3(u1 8 分、u2 31 分、u3 1 分)/ 計画(intent 承認 → plan 承認): 8 分 / reviewer: plan 5 分、test 19 分 / CI 失敗: 0 回 / PR の人間レビューコメント: 0 件

## 次の intent への申し送り

- STOP_SKIP はこの intent では 0 回。次の intent 以降で実際に skip が起きるかを見る。unit 数を超えたら ADR-0002 を更新して窓と上限を狭める。
- M7(記録に cwd / agent)は agent 定義の指示で汚染がほぼ消えたため優先度を下げる。次は Exercise 13 条件 A(ライフサイクル無しの小さな feature)で計測の比較データを取る。
- `verify.sh --changed` が docs 段のテストを走らせない件は、`/build-unit` の手順 4 に「hook / intent.sh を触った unit は `scripts/verify.sh --only docs` も走らせる」を足すと解決する(次の retro で実施)。
