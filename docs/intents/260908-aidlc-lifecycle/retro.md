# retro — 260908-aidlc-lifecycle

## 何が起きたか

AI-DLC を参照してライフサイクル層(記録・受領証・計画承認 guard・SessionStart 再注入・rules・skill 8 本・plan-reviewer・CI の docs 段)を追加した(PR #21、merge 済み)。
この intent は hook 自体を作る作業だったため事後に作った。ゲートは PR merge 後の次セッションで人間が承認し(HUMAN_TURN は hook が実際に記録)、unit を実績どおり閉じた。
plan-reviewer は NOT-READY を返し、指摘 2 件を決定論的テスト(`harness-shape.test.sh`)に変換した。lefthook が既存の穴(差分モード Biome と `templates/`)を 1 件発見した。

## 学びと行き先

| 学び | 行き先 | 変更(パス) |
|---|---|---|
| 承認の受領証は Agent が発行できないものにする(hook が書き、Agent は読む) | hook + script(強制) | `.claude/hooks/record-human-turn.sh`、`scripts/intent.sh gate approve` |
| 「計画が先」は指示ではなく hook で守る | hook(強制) | `.claude/hooks/guard-plan-approval.sh`、guard-bash §7 |
| `$a。` は bash 3.2 で変数名 `a。` になる | rules(領域固有の事実) | `.claude/rules/harness.md` |
| hook の allow は「JSON を出さない」。テスト helper は空出力を先に判定する | テスト(決定論的) | `scripts/tests/hooks.test.sh` の `decision()` |
| 差分モードの Biome に除外設定のあるパスを渡すと失敗する | verify(決定論的) | `scripts/verify/ts.sh`(`templates/` を落とす) |
| skill / rules / agent の frontmatter とテンプレート同期は目視に頼らない | テスト(決定論的) | `scripts/tests/harness-shape.test.sh`(docs 段) |
| 新しい subagent は作成直後には Agent tool で呼べない | plan §10(既知の穴) | `docs/plan.md` §10 |
| 受領証はローカル層で捏造可能。CI は順序しか見ない | plan §10 + lifecycle.md | PR で `docs/intents/` の diff を読む |
| 事後に intent を作らない(計画が出力になる経路) | lifecycle.md + AC6 | `docs/lifecycle.md` §3 |
| reviewer の指摘は決定論的テストに変換して初めて資産になる | exercise | `docs/exercises/12` §5 |
| staged が残ったまま別ファイルを add すると次の commit に混ざる | memory(個人の作業知見。ハーネスには入れない) | `git add <明示パス>` を徹底。1 回きりの手順ミスなので検査化しない |

## 計測

- gate reject: 0 回(reviewer の NOT-READY はゲート前に反映)
- HUMAN_TURN: 3 回(発言 2、AskUserQuestion 1)
- unit 数: 5(全て done)
- CI 失敗: 0 回(lefthook が 1 回止めた)
- plan-reviewer: NOT-READY 1 回 → 指摘 4 件中 2 件をテストに変換、2 件を文書に反映

## 次の intent への申し送り

- intent を必須にするか(`HARNESS_REQUIRE_INTENT=1`)。まず任意で運用し、次の retro で「intent 無しで apps を触った回数」を数える。
- `/retro` の学びの振り分け(memory.md → 行き先)を機械化するか。今は手順のみ。
- 複数 intent の並行(branch = intent の対応付け)。
- 次の intent からは **作業前に** `/intent` を作り、ゲートが実際に効くことを通常の機能変更で確認する(Exercise 13 の候補: enricher の OG 解析改善など小さな feature で一周する)。
