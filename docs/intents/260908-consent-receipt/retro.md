# retro — 260908-consent-receipt

## 何が起きたか

改善計画 H2(承認の受領証を「在席」から「同意」へ)を `/intent` → `/plan-units` → `/build-unit` ×3 → `/create-pr` → merge(PR #25)で一周した。
plan ゲートは初めて `[gate plan]` 付きの AskUserQuestion で出し、hook が実機で `answer=Approve gate=plan` を記録した(旧形式の intent なので承認自体は旧規則)。
plan-reviewer は NOT-READY 3 件(ターンの意味、既存テストの回帰、時刻定数)を返し、提案の `[gate]` の印はそのまま設計に入った。
test-reviewer は mutation で「legacy 分岐を消すと人間ゼロで承認できる」を見つけ、否定側テストを足した。
rules に書いてあった bash 3.2 の罠(`$a、`)を自分でもう一度踏んだ。指示は 2 回目も守られなかった。

## 学びと行き先

| 学び | 行き先 | 変更(パス) |
|---|---|---|
| `$a、` の罠は rules に書いても再発した。検査にする | テスト(決定論的、最優先) | `scripts/tests/harness-shape.test.sh` 3d(変数の直後の非 ASCII を grep) |
| reviewer に「コピーで作業、`rm -rf` を使わない」と指示すると記録の汚染が 25 件 → 2 件になった | agent 定義(次の subagent が自動で読む) | `.claude/agents/test-reviewer.md`、`plan-reviewer.md` に「作業場所」節 |
| reviewer の壁時計が intent の大半(test-reviewer 56 分 / 82 分中)。見つけるものは価値があるが時間の上限が無い | improvement-plan(新規 M8) | `docs/improvement-plan.md` |
| guard-bash §8 は python3 heredoc の **内容** に `.claude/hooks/` があるだけで ask になる(docs を編集しただけで 4 件)。誤検知の実測 | improvement-plan M2 の実測(retro に記録。hook は変えない) | この retro |
| AskUserQuestion の応答形式は公式に明記が無い。形非依存の取り出し(文字列リーフの完全一致)で実機を通った | memory.md(既に記録)+ hook のコメント | `.claude/hooks/record-human-turn.sh` |
| 「ターンを終える」は AskUserQuestion では意味が変わる(回答は同一ターンに返る)。approve は回答直後に同じターンで | skill + rules(既に u3 で反映) | `.claude/skills/{intent,plan-units}`、`.claude/rules/intents.md` |
| reviewer の想定した失敗分岐がテスト結果と違った(別ゲートの Approve は「Approve ではありません」分岐)。2 理由を許す expect_fail はそれを隠す | テスト(1 理由に絞った) | `scripts/tests/intent.test.sh` |

## 計測(`scripts/intent.sh metrics` の出力)

```
HOOK_DENY	1
HOOK_ASK	7
STOP_BLOCK	0
POST_EDIT_FAIL	0
HUMAN_TURN	8
GATE_REJECTED	0
elapsed_sec	5792
```

deny: 1 回(うち誤検知 1。subagent の `rm -rf /tmp/...`)/ ask: 7 回(本体 6: hook 編集 1、テンプレート cp 1、docs を編集する python3 heredoc の内容に hook パスがあった 4。subagent 1)/ Stop block: 0 / post-edit 失敗: 0 / HUMAN_TURN: 8(うち AskUserQuestion 3)/ gate reject: 0 / 経過: 97 分(作成 → close 直前)
unit 数: 3(u1 5 分、u2 2 分、u3 2 分)/ 計画(intent 承認 → plan 承認): 15 分 / reviewer: plan 10 分、test 56 分 / CI 失敗: 0 回 / PR の人間レビューコメント: 0 件

本体の作業でハーネスに止められたのは 6 回、全て ask。うち 4 回は誤検知(docs の編集)。前回(H1)の 29 件から subagent 由来がほぼ消え、計測が読めるようになった。

## 次の intent への申し送り

- 次の intent から `Receipt: consent` になり、ゲートは `[gate <g>]` 付き AskUserQuestion でしか承認できない。テキストで「approve」と打っても通らない。
- H4(Stop hook と halt-and-ask の衝突)が次。M7(記録に cwd / agent)は agent 定義への指示でかなり減ったが、恒久対処は残る。
- M8(reviewer の時間予算)を改善計画に追加した。次の intent で test-reviewer の所要時間を note する。
- docs を python3 heredoc で編集する時、内容に hook パスがあると guard-bash §8 が ask になる。Edit ツールを使えば起きない(M2 の実測として残す)。
