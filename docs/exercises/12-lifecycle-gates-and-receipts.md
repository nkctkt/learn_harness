# Exercise 12 — ライフサイクル型ハーネス: 承認ゲート、受領証、計画承認前の書込拒否(AI-DLC 参照)

- Phase: 9
- 日付: 2026-09-08
- PR: phase9/aidlc-lifecycle
- 記録: `docs/intents/260908-aidlc-lifecycle/`(この演習自身が最初の intent)

## 1. 概念: ハーネスが覆っていなかった区間

Phase 0〜8 のハーネスは「コードを書いてから merge するまで」を守る。しかし AI Agent の失敗は書く前にも起きる:
**勝手に決める**(意図の取り違え)、**勝手に始める**(計画を書かずに実装し、後から計画を「出力」する)、**勝手に承認する**(「承認されたものとして」進む)、
**忘れる**(セッションを跨いで文脈を失う)、**学ばない**(同じ失敗を次の変更で繰り返す)。

AWS の AI-DLC(`../aidlc-workflows` v2.7)はこれを 5 フェーズ 33 ステージの状態機械で解く。本 Phase はそのうち **仕組みだけ** を借りた(`docs/plan.md` §12、ADR-0001):

| 借りた仕組み | 本質 |
|---|---|
| record dir + 追記専用の監査ログ | 状態をチャットではなく Git のファイルに置く |
| HARD STOP(ゲートを出したらターンを終える) | 承認は「Agent の推論の外」で起きる |
| HUMAN_TURN 受領証 | 人間の在席を **hook が** 書き、Agent は読むだけ。承認の捏造を塞ぐ |
| plan-approval guard | 「計画が先」を指示ではなく hook で守る |
| SessionStart の再注入 / memory 層 / Learnings Ritual | 忘れない・肥大化しない・学びを書き戻す |

## 2. 導入したもの

| 層 | 追加 | 何を保証するか | 保証しないもの |
|---|---|---|---|
| script | `scripts/intent.sh`(new / gate / stage / unit / note / close / check、約 300 行、依存なし) | 状態遷移の順序(intent 承認 → inception、plan 承認 → construction、全 unit 完了 → handoff)。提示後に HUMAN_TURN が無い承認の拒否 | 記録の内容の妥当性 |
| 記録 | `docs/intents/<id>/{intent,plan,state,memory,retro}.md` + `audit.log`(TSV) | 「なぜ」「何を」「誰が承認した」が PR に残る | 承認者が読んだかどうか |
| Hook | `record-human-turn.sh`(UserPromptSubmit / PostToolUse:AskUserQuestion) | 人間の在席の記録を Agent の手から離す | ローカルでの `audit.log` 改竄 |
| Hook | `guard-plan-approval.sh`(PreToolUse Edit/Write) | active intent の計画が未承認なら `apps/ services/ packages/ infra/ contracts/` を deny | Bash の heredoc(guard-bash §7 が同条件で deny)以外の書込経路 |
| Hook | `session-start.sh`(SessionStart) | intent の状態と hook の `bash -n` 結果を注入 | - |
| Hook 更新 | guard-edit(`state.md` / `audit.log` を deny)、guard-bash(受領証操作を ask、計画未承認の書込を deny) | 正規の入口(`intent.sh`)以外からの状態変更 | 他ツール経由 |
| L1 | `.claude/rules/{api,web,enricher,shortener,infra,harness,intents}.md`(`paths:`) | 領域固有の事実が、その領域を触る時だけ読まれる | 守られること(request に過ぎない) |
| L2 | `/intent` `/plan-units` `/adr` `/build-unit` `/create-pr` `/release` `/incident` `/retro` | 各タスクの手順とゲートの出し方 | 手順を飛ばさないこと |
| 助言 | `plan-reviewer` subagent | 計画の穴(AC の取りこぼし、walking skeleton、検証不能な DoD、未申告の境界) | block(承認は人間) |
| CI | `verify.sh --only docs`(`security.yml` infra job) | 受領証の順序、state と audit の一致、必須節、unit DAG の循環 | 順序が正しい改竄 |
| テスト | `scripts/tests/{intent,hooks}.test.sh`(41 + 35 assertions、一時ディレクトリ) | intent.sh と hook の振る舞い | - |

hook 3 本は全て「intent が無ければ何もしない」。小さな修正に儀式を強いると、Agent(と人間)は intent を作らない方向に学習する。

## 3. 意図的に壊す → 検出

### 3.1 計画未承認のままアプリを書く(この実セッションで実行)

intent `260908-aidlc-lifecycle` を作り、`plan.md` を書いた直後(`Gate plan: pending`)に:

| 操作 | 結果 |
|---|---|
| Write `apps/api/src/EXERCISE-12-should-be-denied.ts` | **deny**(guard-plan-approval)「計画が未承認です … 計画を後から書くことは禁止です」 |
| Bash `echo 'export const y = 1;' > apps/api/src/EXERCISE-12-bash.ts` | **deny**(guard-bash §7)。ファイルは作られなかった |
| Write `docs/lifecycle.md`、`.claude/skills/*` | allow(保護領域外。`.claude` は guard-edit の ask) |

### 3.2 人間不在で承認する(`scripts/tests/intent.test.sh`)

```
gate present intent → gate approve intent
  ✘ intent: 承認できません: gate 'intent' を提示した後に人間の応答(HUMAN_TURN)が記録されていません
```

`gate reject` → `gate present` をやり直した後、**古い HUMAN_TURN は再利用できない**(提示より前の応答は数えない)ことも確認。

### 3.3 記録を改竄する(`intent.test.sh` の check 4 種)

| 改竄 | `intent.sh check` |
|---|---|
| `audit.log` から HUMAN_TURN を消す | ✘ 提示と承認の間に人間の応答がありません |
| `state.md` だけ approved にする | ✘ state.md は approved ですが audit.log の最終イベントは GATE_PRESENTED |
| `plan.md` の units に循環(u1 → u2 → u1) | ✘ cycle among units |
| 未宣言の unit に依存 | ✘ undeclared: u1-skeleton -> u9-ghost |
| `intent.md` の「スコープ外」を消す | ✘ intent.md に '## スコープ外' がありません |

CI では `security.yml` の infra job が `scripts/verify.sh --only infra,docs` で同じ check を走らせる。

### 3.4 Agent が受領証を自分で書く

`scripts/intent.sh human-turn me` を Bash から呼ぶと guard-bash が **ask**(deny ではない: hook のテストや人間の操作で必要になる)。
`audit.log` への `>>` も ask。Edit / Write は guard-edit が deny。
**これはローカル層なので最終的には防げない**(`docs/plan.md` §10 に追記)。露見させるのは CI の順序検査と、PR レビューで `docs/intents/` の diff を読むこと。

## 4. 踏んだこと

- **`$a。` は bash 3.2 で `a。` という変数名になる**(`unbound variable`)。多バイト文字は変数名の一部として扱われる。`${a}。` と書く(`rules/harness.md` に追記)。
- **新しい subagent は作成直後には呼べない。** `plan-reviewer.md` を書いた直後に Agent tool で指定すると "not found"(数十分後に認識された)。general-purpose agent に定義ファイルを読ませて代用した。skill は即時に認識された。
- **テストの helper で「出力なし = allow」を扱い忘れた。** `jq -r '... // "allow"'` は入力が空だと何も出さない。hook の allow は「JSON を出さない」なので、空を先に判定する。
- **この intent 自身は事後に作った**(計画承認前のコードを禁止する hook を作る作業だったため)。`memory.md` の Deviations に記録。次の intent からはゲートが効く。
- guard-bash §6 の正規表現は `human-turn` と `docs/intents/.../(state.md|audit.log)` を含み、かつ書込系の語(`>`、`sed -i`、`tee`、`mv`、`rm`、`cp`)がある時だけ ask にした。`scripts/intent.sh status` や `gate present` は allow(テストで確認)。

## 5. plan-reviewer の結果(この plan.md に対して)

Verdict: **NOT-READY**(承認前に直す、が正しく機能した)。

| 観点 | 指摘 | 対応 |
|---|---|---|
| 3 DoD の検証可能性 | u4 の DoD「skill が一覧に出る」「rules が paths を持つ」が目視依存で、verify のどの段からも検証されない | `scripts/tests/harness-shape.test.sh` を追加(SKILL.md の name / description と ディレクトリ名一致、rules の `paths:`、agent の name / description / tools)。docs 段で走る。DoD をテスト名に書き換えた |
| 1 AC の整合 | AC3 の「4 種」と検証計画の「×5」が合わない | AC3 を 5 種(未宣言 unit への依存を追記)に修正 |
| 6(要確認) | 「作ってから intent を書いた」はこの仕組みの回避そのもの。再発防止の明記が無い | `docs/lifecycle.md` §3 と AC6 に「intent は作業の前に作る。事後はブートストラップのみ」を明記 |
| 3(要確認) | u5「templates が同期され」が目視 diff 頼み | 同 test に template drift 検査(同一であるべきファイルの byte 一致)を追加。**追加した瞬間に、自分自身(harness-shape.test.sh)が未同期であることを検出した** |

良い点として挙げられたもの: u1 が「機能」ではなく「状態機械の縦串」として定義され hook より先に固める順序に理由があること、ADR-0001 → plan §12 → units の順で不可逆判断を先に固定したこと。
教訓: reviewer の指摘のうち 2 件はそのまま **決定論的テストに変換できた**。助言は変換して初めて資産になる(harness-architecture §2 Subagents の原則どおり)。

## 6. Phase 9 で得たもの

| 問い | 答え |
|---|---|
| 承認を「Agent の主張」から「ハーネスの事実」にするには | 受領証を Agent が発行できないものにする(UserPromptSubmit hook が書く)。Agent はそれを読む側に置く |
| 「計画が先」を守らせるには | 指示ではなく PreToolUse hook。「計画未承認 × 保護領域」の 2 条件で deny |
| セッションを跨いで状態を保つには | 状態は Git のファイル、SessionStart で読み直す。チャットの記憶に頼らない |
| AGENTS.md を 200 行以内に保つには | 領域の事実は `rules/`(`paths:`)、手順は skill、強制は hook。AGENTS.md に残るのは「どれを使うか」だけ |
| 学びを次に効かせるには | `/retro` を close の前提にする(`retro.md` が無いと close できない)。行き先は決定論的な方を優先 |

## 7. 残課題

- この intent のゲートを人間が通す(`gate approve intent` → `stage inception` → `gate approve plan` → `stage construction` → 各 unit を start / done → `stage handoff`)。AC6。
- intent を必須にするか(`HARNESS_REQUIRE_INTENT=1`)。まず任意で運用し、次の retro で「intent 無しで apps を触った回数」を数えて決める。
- `/retro` の学びの振り分けを機械化する(AI-DLC の `aidlc-learnings.ts` 相当)。今は手順(skill)のみ。
- 複数 intent の並行(branch = intent の対応付け)。
