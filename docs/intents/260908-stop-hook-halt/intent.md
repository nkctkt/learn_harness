# 260908-stop-hook-halt

- Scope: harness
- 作成: 2026-09-08
- 出典: `docs/improvement-plan.md` H4(Stop hook と halt-and-ask が衝突する)

## 目的

lifecycle は「計画から外れたら `note "Open questions"` を残してターンを終えて人間に聞け」と言い、ゲートを提示した時も人間の応答を待ってターンを終える。
しかし Stop hook は、未コミットの変更で `verify.sh --changed` が落ちる限りターン終了を block する。落ちたテストを抱えたまま人間に相談する経路が、設計上は許されているのに機械的には塞がれている。
Agent が「人間に聞きたい」状態(ゲート提示中、または直近に Open questions を残した)にある時は Stop hook が verify を skip し、その事実を記録して、相談の経路を開けるようにする。
skip は隠さず `STOP_SKIP` として audit.log に残し、`/retro` が回数を読めるようにする。CI(全体 verify)が最終防衛線であることは変わらない。

## スコープ外

- Stop hook の verify の内容や範囲の変更(`--changed` のまま)
- ゲート提示・Open questions 以外の理由での skip(例: 時間切れ、環境変数による無効化)。逃げ道は 2 つだけ
- 改善計画の他項目(M7 記録の cwd / agent、M8 reviewer の時間予算、M 系)
- `stop_hook_active` の扱い(既存のまま)

## 受け入れ条件

- [ ] AC1: active な intent の `Gate intent` か `Gate plan` が `presented` で、その `GATE_PRESENTED` が **600 秒以内** の時、stop-verify は verify を走らせず exit 0 で終わり、`audit.log` に `STOP_SKIP gate=<g>` を記録する。600 秒より古い提示では skip しない(`scripts/tests/hooks.test.sh`、`intent.test.sh`)
- [ ] AC2: 直近 600 秒以内に `NOTE Open questions` が `audit.log` にある時、同様に skip し `STOP_SKIP open-questions` を記録する。600 秒より古い note では skip しない(`hooks.test.sh`、`intent.test.sh`。テストは audit.log の時刻を書き換えて期限切れを作る)
- [ ] AC2b: 600 秒以内の `STOP_SKIP` が既に 3 件あれば、条件を満たしても skip しない(note の連発で無期限に延長できない)(`intent.test.sh`)
- [ ] AC3: 上記以外(ゲート未提示・note 無し・intent 無し)は従来どおり verify を走らせ、失敗なら exit 2 と `STOP_BLOCK`(`hooks.test.sh` の既存 assertion が全て通る)
- [ ] AC4: `intent.sh metrics` が `STOP_SKIP` を合計と理由別(`gate=` / `open-questions`)に数え、`/retro` の計測欄に「Stop skip(理由別)」が入る(`scripts/tests/intent.test.sh`、`harness-shape.test.sh`)
- [ ] AC5: `/build-unit` と `/plan-units` の halt-and-ask 手順と `docs/lifecycle.md` に「相談のためにターンを終える時は Stop hook が verify を skip する。落ちたテストは CI が受ける」が書かれ、templates が同期されている(`harness-shape.test.sh` の grep と drift 検査)

## リスクと HITL レベル

- 触れる信頼境界: ハーネス自体(`stop-verify.sh`、`scripts/intent.sh`(metrics)、`scripts/tests/*`、skill 2 本、retro skill、`docs/lifecycle.md`、templates)
- HITL: 4(scope=harness)
- 想定されるリスク:
  - Agent が `note "Open questions"` を書くだけで Stop hook を回避できる → 回避は 600 秒の窓と窓内 3 回の上限に限られ(ゲート提示も同じ窓)、`STOP_SKIP` が理由別に audit.log に残り、metrics と retro で回数が見える。CI の全体 verify が落ちれば merge できない(Rulesets)。常態化したら ADR-0002 を更新して窓と上限を狭める
  - この intent が触るファイル(`scripts/intent.sh`、`scripts/tests`、skill、docs、templates)はどの guard の deny / ask にも掛からない。Stop hook を緩める変更が verify 無しで進む経路を、600 秒の窓と 3 回の上限で閉じる
  - `intent.sh` が壊れていると skip 条件を読めない → その場合は skip しない(従来どおり verify を走らせる)。fail-closed の方向は「block する側」
  - 「ゲート提示中」は consent 方式では同一ターン内に回答が返るため短いが、Request Changes 後に直して再提示するまでの間は presented のまま → その間の Stop も skip される。これは意図どおり(人間が輪の中にいる)
