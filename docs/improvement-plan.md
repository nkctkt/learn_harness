# 改善計画 — 「開発生産性と品質の両立」の観点でハーネスを見直す

- 作成日: 2026-09-08
- 対象: Phase 0〜9 の成果物(hooks / verify / CI / Rulesets / lifecycle / skills / docs / templates)
- 前提: `docs/plan.md` §10(既知の穴)と `docs/intents/260908-aidlc-lifecycle/retro.md` の申し送りを引き継ぐ
- 位置づけ: 次の Phase(10)の入力。着手する項目は `/intent --scope harness` から始める

## 1. 診断

品質側は層(hook → pre-commit → CI → Rulesets → Nightly)が揃い、各ゲートに「無いと何が起きるか」の根拠が残っている。
一方で **生産性は一度も測られていない**。docs 全体に「生産性」「リードタイム」「所要時間」という語は無く、retro の計測欄は gate reject と HUMAN_TURN の回数だけ。
現状のハーネスは「品質のために生産性を削っても気づけない」構造であり、「両立している」ではなく「品質側だけ検証済み」が正確。

### 1.1 規模

| 区分 | 行数 |
|---|---|
| アプリ本体(TS / Py / Go、テスト除く) | 946 |
| アプリのテスト | 1,043 |
| ハーネス(hooks / scripts / skills / policies / workflows / settings) | 3,285 |
| docs | 2,329 |
| templates | 3,683 |

アプリ 1 に対しハーネス + docs + テンプレートが約 10。学習用なので比率は問題ではないが、ハーネスの変更コストがアプリの変更コストを支配している。

### 1.2 実測(2026-09-08、ローカル)

| 経路 | 時間 | 判定 |
|---|---|---|
| Edit 1 回の PreToolUse hook 3 本 | 60 ms | 問題なし |
| Bash 1 回の PreToolUse hook 2 本 | 30 ms | 問題なし |
| PostToolUse `verify.sh --fix --files`(ts / py) | 1.2〜1.8 秒 | 問題なし |
| Stop hook 相当(tsc + vitest、1 パッケージ) | 1.3〜1.6 秒 | 問題なし(規模が増えると要再測) |
| `verify.sh --only docs`(intent check + hook テスト 3 本) | 1.8 秒 | 問題なし |
| CI 壁時計(`docs/ci-design.md`) | 2〜3 分 | 問題なし |
| PR 作成 → merge | 大半 2〜30 分。例外: #3 484 分、#13 109 分、#19 118 分 | 内訳不明(計測が無い) |
| merge 済み PR の人間のレビューコメント | 0 件(bot のみ 6 件) | L10 は名目 |

hook と CI の遅延はボトルネックではない。時間が消えているのは「儀式(intent / plan / reviewer / retro)」と「ハーネス自体の保守(テンプレート同期、誤検知の修正)」であり、その量は記録されていない。

## 2. 改善項目

優先度: **高** = 両立を壊している、または両立を検証できない。**中** = 生産性を静かに削っている。
層: hook(L3)/ script / CI(L7)/ policy(L9)/ skill(L2)/ docs。

### 高

| # | 問題 | 改善 | 層 | 検証(DoD) |
|---|---|---|---|---|
| H1 | **生産性の計測が無い。** deny / ask / Stop block の回数、verify の時間、unit あたりのターン数がどこにも残らない | hook が判定を 1 行追記する(intent 中は `audit.log` に `HOOK_DENY` / `HOOK_ASK` / `STOP_BLOCK`、intent 外は `.claude/metrics.log`、後者は gitignore)。`/retro` の計測欄に「deny 回数 / Stop block 回数 / intent 作成 → merge の時間 / Edit 失敗回数」を必須項目にする | hook + skill | `hooks.test.sh` に「deny 時に audit に HOOK_DENY が書かれる」を追加。`intent.sh check` は既存イベント以外を無視することを確認 |
| H2 | **受領証が「在席」であって「同意」ではない。** `HUMAN_TURN` はどんな入力でも付く(「続けて」でも)。`gate approve` を実行するのも人間の文を Approve と解釈するのも Agent。実際の audit.log では 2 ゲートが同秒に提示・同秒に承認され、check はそれを通した | `gate approve` が受け付ける受領証を `PostToolUse:AskUserQuestion` 由来に限定し、hook が回答本文(Approve / Request Changes)を `HUMAN_TURN` の detail に書く。`intent.sh check` は「承認の直前の HUMAN_TURN が AskUserQuestion:Approve であること」を検査する | hook + script + CI | `intent.test.sh`: UserPromptSubmit 由来だけでは approve が拒否される / AskUserQuestion:Approve なら通る / Request Changes なら拒否 |
| H3 | **儀式コストが固定で軽量経路が無い。** 1 feature で intent.sh 約 15 回、ブロッキングターン最低 2 回、plan-reviewer + test-reviewer(実測 13 分)、retro.md 必須。「小さな修正は不要」の境界を Agent が判断しており、それはハーネスが信用していない主体そのもの | `scripts/intent.sh classify` を足し、diff から決定論的に tier を出す(例: 1 パッケージ内・境界ファイル(schema / contracts / clients / infra / policies)に触れない・変更 100 行以下 → `light`)。`light` は intent のみで plan gate を省略、`bugfix` scope は intent と plan を 1 ターンで承認可。guard-plan-approval と skill は tier を読む | script + hook + skill | `intent.test.sh`: 境界ファイルを含む diff は `full`、含まない小 diff は `light`。`light` で plan 未承認でも apps/ に書ける |
| H4 | **Stop hook と halt-and-ask が衝突する。** lifecycle は「計画から外れたら note を残してターンを終えて聞け」と言うが、Stop hook は verify が落ちる限りターン終了を block する。落ちたテストを抱えて相談する経路が塞がれている | `stop-verify.sh` は active intent の gate が `presented`、または直近 10 分以内に `NOTE Open questions` がある時は skip し、その事実を stderr に出す | hook | `hooks.test.sh`: presented 中は verify 失敗でも exit 0 / それ以外は exit 2 |
| H5 | **「最後の防衛線は PR で `docs/intents/` の diff を読む」に実績が無い。** 人間のレビューコメント 0 件、approvals 0、CODEOWNERS は本人。L10 は名目 | (a) `docs/harness-architecture.md` §2 L10 に「単独メンテナでは名目」と明記する。(b) CI の docs 段が PR に「intent 要約 + 受領証の並び(PRESENTED → HUMAN_TURN → APPROVED)+ 触れた境界」を job summary として貼り、人間が読む量を絞る | docs + CI | job summary に受領証の並びが出る(目視)。docs の記述を更新 |

### 中

| # | 問題 | 改善 | 層 | 検証(DoD) |
|---|---|---|---|---|
| M1 | **テンプレート同期が二重編集を強制する。** 28 ファイルの byte 一致を CI が要求し、`/retro` で hook を直すたびに cp が要る(実測: 260908-harness-metrics で同期の `cp` が guard-bash §8 の ask を 3 回発生させた) | `scripts/sync-template.sh` を作り lefthook の pre-commit で自動実行(同一であるべき一覧は `harness-shape.test.sh` と共有)。テンプレート側は生成物として扱う | script + pre-commit | commit 後に `harness-shape.test.sh` の drift 検査が常に通る |
| M2 | **誤検知の逃げ道が無い。** guard-bash は文字列リテラル内の回避フラグにも反応し(既知 3 件。実測追記: python3 heredoc の内容に hook パスがあるだけで §8 が ask、audit.log を読む grep に `2>&1` を付けただけで §6 が ask(後者は H4 の retro で修正))、回避には hook 編集(HITL-4 + CODEOWNERS + 同期)しかない | 理由付き override: `HARNESS_OVERRIDE="<reason>"` を環境変数で与えた Bash は deny が ask に格下げされ、理由が audit(`HOOK_OVERRIDE`)に残る。黙って hook を緩める経路を塞ぐ | hook | `hooks.test.sh`: override なしは deny / ありは ask + audit 行 |
| M3 | **active intent が branch と結びついていない。** intent が残っていると無関係な小修正まで deny される(plan §10) | `state.md` に `Branch:` を記録し、guard-plan-approval と guard-bash §7 は現在の branch が一致する時だけ効かせる | script + hook | `hooks.test.sh`: 別 branch では deny されない |
| M4 | **post-edit-check の `--fix` が Agent の背後でファイルを書き換える。** 整形後の内容を Agent は知らず、次の Edit が old_string 不一致で失敗し得る。頻度は未計測 | H1 の計測に「Edit 失敗回数」を含め、実害があれば `--fix` を止めて指摘のみにする | hook | 計測結果を次の retro に載せる。判断はそこで |
| M5 | **Dependabot の PR が 5 件溜まっている。** CODEOWNERS 承認が要る設計は意図どおりだが、更新が止まっており品質の劣化 | cooldown 7 日を通過し CI が緑の actions / patch 更新は auto-merge を許可する(`.github/workflows/auto-merge.yml` + Rego で対象を限定) | CI + policy | 対象外(major / 新規依存)は auto-merge されないことを Rego のテストで確認 |
| M6 | **HUMAN_TURN が毎プロンプトで audit.log に積まれ、PR の diff にノイズが出る**(実害: merge 後の `git checkout main` が audit.log の未コミット差分で止まった。260908-harness-metrics と 260908-stop-hook-halt の retro、2 回) | 連続する HUMAN_TURN は直近 1 件だけ残す(gate の判定に必要なのは「提示より後に 1 件あるか」だけ) | script | `intent.test.sh`: 連続 3 回の human-turn で audit 行が 1 行 |
| M7 | **記録が「誰の・どこでの判定か」を区別しない。** subagent(test-reviewer)が `/tmp` のコピーで行った mutation テストの Bash が本体の guard-bash を通り、intent の audit.log に HOOK_ASK 22 件 / HOOK_DENY 2 件として混ざった(260908-harness-metrics: 29 件中 25 件が subagent 由来)。metrics の分母が汚れる | hook 入力の `cwd`(と、あれば agent 識別子)を `event` の detail に含め、`metrics` が `cwd ≠ repo` を別集計する。guard-bash 自体の判定は変えない | hook + script | `hooks.test.sh`: cwd が repo 外の deny が `[external]` 付きで記録され、metrics が別行で数える |
| M8(**済** 260908-stop-hook-halt の retro で agent 定義に固定)| **reviewer subagent の壁時計が intent の大半を占める。** H2 で test-reviewer 56 分 / plan-reviewer 10 分(intent 全体 82 分)。mutation を 1 件ずつ手で回すため | reviewer の prompt に時間予算(例 15 分)と「mutation は最大 N 件、対象は差分のテストだけ」を書く。`/create-pr` は reviewer の所要時間を memory に note する(計測) | agent + skill | 次の intent の retro で test-reviewer の所要時間が 20 分以内 |

### 手を付けない(理由付き)

| 候補 | 理由 |
|---|---|
| hook / Stop hook / CI の高速化 | 実測でボトルネックではない(§1.2)。規模が 10 倍になった時に再測 |
| Claude sandbox の導入 | `docs/harness-architecture.md` §6 の設計のまま。宛先の洗い出しが先 |
| reviewer subagent の廃止 | test-reviewer は 13 分で 1 件のバグを見つけた。費用対効果は H1 の計測が揃ってから判断。実測(H2): plan-reviewer 10 分、test-reviewer **56 分**で、intent の壁時計 82 分の大半が reviewer 待ち。見つけた欠陥は重大 1 + 中 2(全て mutation で実証)。廃止はしないが、M8 として時間の上限を検討 |
| Rulesets の approvals を 1 にする | 単独メンテナでは admin bypass が常態化する(plan §8)。H5 の docs 明記で対応 |

## 3. 検証の設計: Exercise 13 を計測付きの実験にする

retro の申し送り「通常の feature で /intent を一周する」を、単に一周するのではなく **同じ feature を 2 回** 実装して比較する。

- 題材: enricher の OG 解析改善(小さく、境界(外部 fetch)に触れる)
- 条件 A: ライフサイクル無し(intent を作らず、Stop hook + CI のみ)
- 条件 B: ライフサイクル有り(`/intent` → `/plan-units` → `/build-unit` → `/create-pr` → `/retro`)
- 計測(H1 が入ってから): ターン数、壁時計、deny / ask / Stop block 回数、Edit 失敗回数、人間のブロッキングターン数、見つかった欠陥数と発見した層
- 判定: B の追加コストが「B だけが見つけた欠陥」で正当化できるか。できないなら H3 の `light` tier の閾値を上げる

結果は `docs/exercises/13-*.md` に残し、`docs/lifecycle.md` §5 に「どの規模から lifecycle を課すか」の実測根拠として書く。

## 4. 着手順

1. H1(計測)。他の全項目の判断材料になる。`--scope harness`、HITL-4
2. H2(同意の受領証)と H4(Stop と halt-and-ask)。どちらも数十行で、hook テストで閉じる
3. Exercise 13(条件 A)を実施し、H1 のデータを 1 セット取る
4. H3(軽量経路)。閾値は 3 のデータで決める
5. Exercise 13(条件 B)を実施し、比較を書く
6. M1〜M8 は 1〜5 の合間に、1 項目 1 intent で。M7 は計測の分母を汚すので H3 の閾値を決める(4)より前に入れる

各項目の変更は `.claude/**` `scripts/**` `policies/**` `.github/**` に及ぶため PR に理由を書く(AGENTS.md)。テンプレート同期は M1 が入るまで手動。
