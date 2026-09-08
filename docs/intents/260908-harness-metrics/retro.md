# retro — 260908-harness-metrics

## 何が起きたか

改善計画 H1(生産性の計測)を、通常の手順どおり `/intent` → `/plan-units` → `/build-unit` ×3 → `/create-pr` → merge(PR #23)で一周した。ゲートが実際に効いた最初の intent。
plan-reviewer は NOT-READY(4 件)を返し、全て計画に反映した。test-reviewer は実装を 1 箇所ずつ壊す mutation で「落ちないテスト」を 2 件見つけ、テストに変換した。
hook 6 本が判定を記録するようになり、この intent 自身の記録が最初のデータになった。その 29 件の HOOK_ 行のうち 25 件は test-reviewer subagent が `/tmp` のコピーで行った mutation テスト由来だった(計測の分母が汚れる、という新しい穴)。
merge 後の `git checkout main` は hook が書いた audit.log の未コミット差分で止まった(改善計画 M6 の実害)。

## 学びと行き先

| 学び | 行き先 | 変更(パス) |
|---|---|---|
| guard-bash はパスの位置を見ない。`/tmp` のコピーへの `sed -i` も ask になり audit.log に混ざる | rules(領域固有の事実) | `.claude/rules/harness.md` |
| テンプレートへの `cp` が guard-bash §8 の ask になる(3 回) | rules + improvement-plan M1 の実測 | `.claude/rules/harness.md`、`docs/improvement-plan.md` |
| audit.log の未コミット差分は hook が書いたもの。checkout 前に commit に含める | rules(領域固有の手順) | `.claude/rules/intents.md` |
| 記録は「誰の・どこでの判定か」を区別しない。subagent の mutation テストが分母を汚す | improvement-plan(新規 M7、H3 の閾値決定より前に) | `docs/improvement-plan.md` |
| reviewer の指摘は決定論的テストに変換して初めて資産になる(前回の学びの再確認: 今回は 3 件) | テスト(決定論的) | `scripts/tests/{intent,hooks}.test.sh` |
| `grep -q` にパイプで直接つなぐと pipefail で偽の失敗になる。出力は変数に取ってから grep する | テスト内コメント(1 回きりの手順ミス。検査化しない) | `scripts/tests/intent.test.sh` |
| Edit の失敗回数(old_string 不一致)は hook から観測できない | retro に理由(何もしない) | Claude Code 側に PostToolUseFailure 相当の hook が無い限り不可。Exercise 13 では人間が数える |

## 計測(`scripts/intent.sh metrics` の出力)

```
HOOK_DENY	2
HOOK_ASK	27
STOP_BLOCK	0
POST_EDIT_FAIL	0
HUMAN_TURN	5
GATE_REJECTED	0
elapsed_sec	3235
```

deny: 2 回(うち誤検知 2。subagent が `/tmp` のコピーで `rm -rf` と `git reset` を実行)/ ask: 27 回(うち本体の作業 7: hook 編集 4、テンプレート同期 3。subagent 由来 20)/ Stop block: 0 / post-edit 失敗: 0 / HUMAN_TURN: 5 / gate reject: 0 / 経過: 54 分(作成 → close 直前)
unit 数: 3(u1 2 分、u2 17 分、u3 2 分)/ CI 失敗: 0 回 / PR の人間レビューコメント: 0 件

本体の作業だけを見ると「ハーネスが止めた」のは 7 回、全て HITL-4 の ask(hook とテンプレートを触る intent なので妥当)。誤検知は subagent 由来の 2 deny のみ。

## 次の intent への申し送り

- M7(記録に cwd / agent を含める)を先に入れないと、subagent を使う intent の metrics は読めない。H3 の閾値決定(着手順 4)より前に。
- H2(同意の受領証)と H4(Stop hook と halt-and-ask の衝突)は計画どおり次。
- Exercise 13 条件 A(ライフサイクル無し)の計測は、これで hook 側の準備が整った。人間が数えるのはターン数・壁時計・Edit 失敗回数。
- 改善計画の「手を付けない: reviewer subagent の廃止」は据え置き。test-reviewer は 15 分で重大 2 件を見つけ、いずれも mutation で実証されていた。
