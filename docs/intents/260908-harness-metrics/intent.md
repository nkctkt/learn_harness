# 260908-harness-metrics

- Scope: harness
- 作成: 2026-09-08
- 出典: `docs/improvement-plan.md` H1(生産性の計測が無い)

## 目的

ハーネスが自分の判定(deny / ask / Stop block / 編集後チェックの失敗)と、人間の関与(HUMAN_TURN、gate reject)を機械的に記録し、
`/retro` が「この intent でハーネスは何回 Agent を止め、それに何分かかったか」を数字で言えるようにする。
これが無いと改善計画の H2〜M6 の効果を測れず、Exercise 13(ライフサイクル有り / 無しの比較)も感想文になる。
ハーネスの摩擦を、Agent の主張ではなくハーネスの事実として残せるようにする。

## スコープ外

- ターン数・トークン数・壁時計の内訳(hook からは観測できない。Exercise 13 では人間が手で記録する)
- Edit の失敗回数(old_string 不一致は PostToolUse に届かない。観測手段の調査だけ memory.md に残す)
- 計測結果の可視化(job summary / グラフ)。`intent.sh metrics` のテキスト出力まで
- 改善計画の他項目(H2 同意の受領証、H3 軽量経路、H4 Stop hook の skip、M 系)。データが揃ってから別 intent
- hook の既存の deny / ask 条件の変更。唯一の例外は guard-bash §6 の ask 対象に `intent.sh event` を **追加** すること(新しい捏造経路を human-turn と同じ扱いにするため。既存条件は緩めも強めもしない)

## 受け入れ条件

- [x] AC1: guard-bash / guard-edit / guard-plan-approval / guard-secrets が deny または ask を返す時、active な intent があれば `audit.log` に `HOOK_DENY` / `HOOK_ASK` と hook 名・短い理由が追記される(`scripts/tests/hooks.test.sh`)
- [x] AC2: stop-verify が exit 2 の時 `STOP_BLOCK`、post-edit-check が問題を返す時 `POST_EDIT_FAIL` が同様に追記される(`hooks.test.sh`)
- [x] AC3: active な intent が無い時は `.claude/metrics.log` に同じ TSV 形式で追記され、そのファイルは gitignore 済み(`hooks.test.sh`、`harness-shape.test.sh`)
- [x] AC4: `scripts/intent.sh metrics` が deny / ask / Stop block / post-edit 失敗 / HUMAN_TURN / gate reject の回数と、INTENT_CREATED から INTENT_CLOSED(未 close なら現在)までの経過時間を出す(`scripts/tests/intent.test.sh`)
- [x] AC5: 新イベントを含む `audit.log` を `scripts/intent.sh check` が通す(受領証の順序検査に影響しない)(`intent.test.sh`)
- [x] AC6: 記録処理が失敗しても(書込先が無い等)hook の判定(deny / ask / exit code)は変わらない(`hooks.test.sh`)
- [x] AC7: `/retro` skill の計測欄テンプレートに新項目が入り、`templates/harness/template/` が同期されている(`harness-shape.test.sh` の drift 検査)

## リスクと HITL レベル

- 触れる信頼境界: ハーネス自体(`.claude/hooks/*`、`scripts/intent.sh`、`scripts/tests/*`、`.claude/skills/retro`、`.gitignore`、`templates/`)
- HITL: 4(scope=harness。CODEOWNERS 承認、guard-edit の ask)
- 想定されるリスク:
  - 記録処理のバグで hook が fail-closed(deny)になり全ツールが止まる → 記録は deny() / ask() ヘルパーの中で判定 JSON を出す **直前** に `|| true` 付きで呼び、`bash -n` と hooks.test.sh で守る(AC6)
  - guard-bash §6 は `audit.log` への書込を ask にする。hook が `intent.sh` 経由で書く分は Bash ツールを通らないので影響しないが、`intent.sh` に hook 専用サブコマンド(`event`)を足すので、Agent が Bash から呼んで捏造できる経路が増える → §6 の ask 対象に `event` も加える
  - `audit.log` の行数が増え PR の diff が読みにくくなる → 記録は判定した時だけ(allow は書かない)。M6 の圧縮は別 intent
