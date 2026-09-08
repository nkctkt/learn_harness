---
name: create-pr
description: 全 unit が完了した intent を PR にする。全体 verify(sec / infra / docs 段を含む)→ test-reviewer → intent / AC / DoD / ハーネス変更の理由 / 意図的欠陥の検出結果を本文に書いて gh pr create → CI を見届ける。AI-DLC の Construction → Operation の受け渡し(handoff)に相当。
argument-hint: "[--draft]"
---

# /create-pr — 人間のレビュー(HITL-3 / 4)に出す

前提: `scripts/intent.sh status` が `stage=handoff`(全 unit `[x]`)。ブランチは `phase<N>/<slug>` か `fix/<slug>`。`main` に直接 push しない。

## 手順

1. **全体モードで検証する**(Stop hook の `--changed` は sec / infra / docs 段を飛ばす)
   ```
   scripts/verify.sh
   ```
   落ちたら直す。CI と同じスクリプトなので、ここで通れば CI もほぼ通る(差はツールのバージョン。`/fix-ci` の表)。
2. **テストの質を見る**: `test-reviewer` subagent(Agent tool)に変更したテストを読ませる。重大(実装を壊しても落ちないテスト)は直す。中以下は判断して `note Tradeoffs` に残す。
3. **記録を最新にする**: `intent.md` の AC チェックボックスを実測で更新。`memory.md` の Open questions に未解決があれば PR 本文に出す。
4. **PR 本文**(この順で。レビュアーが intent を読まなくても判断できるように)
   ```markdown
   ## Intent
   docs/intents/<id>/ — 目的を 1 行。scope、HITL レベル。

   ## 受け入れ条件
   - [x] AC1 … (どのテスト / verify の段で確認したか)

   ## Units
   | unit | DoD | 確認 |

   ## ハーネスの変更(あれば)
   何を守るゲートを追加 / 変更したか。`.github/workflows` `.claude/settings.json` `policies` を触った理由(AGENTS.md の要請)。

   ## 意図的欠陥の検出結果(演習なら)
   作った欠陥 → どの層が止めたか。

   ## レビューで見てほしい所
   memory.md の Deviations / Open questions から。
   ```
5. **作成**: `gh pr create --title "<type>(<scope>): <summary>" --body-file <file>`(`--draft` 指定時は draft)。番号は出力から取る(Dependabot の PR が挟まる)。
6. **CI を見届ける**: `gh pr checks <pr> --watch`。落ちたら `/fix-ci`。緑でも未解決スレッド(code scanning のコメント)があると merge できない(Exercise 07)。
7. merge は人間が行う(`--merge`)。merge 後は `scripts/intent.sh stage operation`(リリースや運用が続く場合)か、そのまま `/retro`。

## やらないこと

- `git push --force`、`--no-verify`(guard-bash が deny)。
- CI を通すためのテスト skip / `continue-on-error` / 閾値緩和。
- intent の無い大きな変更を PR にする(レビュアーに「なぜ」が伝わらない)。
