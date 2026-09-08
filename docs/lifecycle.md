# Lifecycle — 開発ライフサイクルの各タスクとハーネスの要素(Phase 9)

`docs/plan.md` §12 が「AI-DLC から何を借り、何を借りなかったか」。本書は **使う側の地図**: 各タスクで何が起き、どの要素が支援し、どの要素が強制するか。

## 1. 一周の流れ

```
 タスク         Ideation        Inception              Construction            Handoff        Operation         Feedback
 ─────────  ─────────────  ─────────────────────  ───────────────────────  ────────────  ───────────────  ──────────────
 skill      /intent         /plan-units  /adr       /build-unit ×N           /create-pr     /release          /retro
                                                                                          /incident
 記録       intent.md       plan.md  adr/NNNN      state.md の unit [ ]→[-]→[x]  PR 本文       memory.md         retro.md
            state.md        state.md               memory.md(note)
 ゲート     gate intent ▶   gate plan ▶            (halt-and-ask)           Rulesets       タグ = 人間          close
            人間            人間 + plan-reviewer                             ci-ok/security-ok
 強制(L3)  -               guard-plan-approval:   stop-verify(--changed)   -              guard-bash:        intent.sh close は
                            承認まで apps/… deny   post-edit-check                          force / apply deny  retro.md 必須
 強制(L7)  intent.sh check(docs 段): 受領証の順序、state と audit の一致、必須節、unit DAG                  release.yml の
                                                                                          image gate + attest
```

- **stage** は `ideation → inception → construction → handoff → operation`。`scripts/intent.sh stage <x>` が順序を検査する(inception は intent 承認後、construction は plan 承認後、handoff は全 unit 完了後)。
- **ゲートは 2 択**で提示し、提示したらターンを終える。承認は人間の応答(hook が書く `HUMAN_TURN`)が提示より後にある時だけ記録できる。

## 2. 要素の一覧と「無いと何が起きるか」

| 要素 | 種類 | 層 | 支援 / 強制 | 無いと何が起きるか |
|---|---|---|---|---|
| `scripts/intent.sh` | script | 共通 | 両方 | 状態がチャットにしか無い。承認の有無を Agent の記憶に頼る |
| `docs/intents/<id>/` | 記録 | 記録 | - | 「なぜ」が PR にも残らない。セッションを跨ぐと消える |
| `record-human-turn.sh` | hook(UserPromptSubmit / AskUserQuestion) | L3 | 強制(受領証の発行元) | Agent が「承認された」と書ける |
| `guard-plan-approval.sh` | hook(PreToolUse Edit/Write) | L3 | 強制 | 先にコードを書き、計画を後から書く |
| guard-bash §6 §7 / guard-edit | hook | L3 | 強制 | 記録ファイルを Bash / Edit で書き換えられる |
| `session-start.sh` | hook(SessionStart) | L3 | 支援 | 再開時に「どこまでやったか」を人間が説明し直す |
| `.claude/rules/*.md` | 指示(`paths:`) | L1 | 支援 | AGENTS.md が肥大化する。領域固有の事実が読まれない |
| 8 skill | 手順 | L2 | 支援 | 毎回手順を発明する。ゲートを飛ばす |
| `plan-reviewer` | subagent | 助言 | 支援 | 計画の穴を人間だけが探す |
| `verify.sh --only docs` | CI(`security.yml` infra job) | L7 | 強制 | ローカルで改竄された記録が merge される |

支援と強制の境目: **支援は Agent が無視できる**(skill を読まない、rules を守らない)。強制は hook と CI だけ。
Phase 9 で「指示 → hook」に変換したのは 2 つ(計画承認前の書込禁止、承認の受領証)。それ以外の手順は skill(支援)のまま。

## 3. 各タスクの詳細

### Ideation — `/intent`

- 入力: 人間の依頼。出力: `intent.md`(目的 / スコープ外 / 受け入れ条件 / リスクと HITL)。
- 受け入れ条件は「テスト名か verify の段で言える」文にする。ここが曖昧だと DoD も曖昧になり、Stop hook は通るのに意図と違うものができる。
- HITL レベルはここで決める。`.github .claude policies infra` と依存追加は 4。

### Inception — `/plan-units`、`/adr`、`plan-reviewer`

- 出力: `plan.md`(設計判断 / 分解 / 順序と walking skeleton / DoD / 検証計画 / ハーネスへの影響)、`docs/adr/`。
- unit は「独立に実装・検証できる単位」。`depends_on` の DAG は CI が循環と未宣言を落とす。
- u1 は walking skeleton(全結合点を通る最薄の縦串)。機能から始めると結合の問題が最後に出る(Exercise 09 の契約不一致がその例)。
- plan-reviewer は敵対的に読むが block しない。承認は人間。

### Construction — `/build-unit`

- unit ごとに `start → DoD のテスト → 最小実装 → verify → commit → done`。Stop hook(`--changed`)と post-edit-check がここで効く。
- 計画から外れたら halt-and-ask(`note "Open questions"` → ターン終了)。計画の実質が変わるなら承認を取り直す。
- u1 だけは compose で実際に結合を通してから done にする。

### Handoff — `/create-pr`

- 全体モードの `verify.sh`(sec / infra / docs 段は `--changed` では走らない)→ test-reviewer → PR 本文(intent / AC / units / ハーネス変更の理由 / 検出結果)。
- merge は人間(Rulesets: `ci-ok` + `security-ok` + CODEOWNERS + 会話解決)。

### Operation — `/release`、`/incident`

- release: バージョンは人間が決める。タグ → `release.yml` → `gh attestation verify`。タグは消さない。
- incident: scope=bugfix の intent。unit は「再現テスト」と「最小修正」の 2 つ固定。ポストモーテムの中心は「どの層が捕まえるべきだったか」。

### Feedback — `/retro`

- `memory.md` と `audit.log` から学びを取り出し、**次の Agent が自動で読む場所**(rules / hook / verify / skill / exercises)に書き戻す。迷ったら決定論的な方へ。
- `retro.md` が無いと `close` できない。学びをチャットに残して終わる経路を塞ぐ。

## 4. 記録の整合性(CI が見るもの)

`scripts/intent.sh check`(`verify.sh --only docs`)が全 intent について検査する:

1. `state.md` の必須フィールド、`intent.md` の 4 節、(construction 以降なら)`plan.md` の 3 節
2. `GATE_APPROVED` の前に `GATE_PRESENTED` があり、その間に `HUMAN_TURN` がある
3. `state.md` の gate 状態と `audit.log` の最終 gate イベントが一致する
4. stage と承認の順序(inception は intent 承認後、construction は plan 承認後)
5. `plan.md` の `units:` ブロックが宣言済み unit にだけ依存し、循環が無い

検出できないもの: ローカルで `audit.log` に HUMAN_TURN を書き足す改竄(全ローカル層と同じ)。PR レビューで `docs/intents/` の diff を読むのが最後の防衛線。承認した人間が中身を読んだかどうか。

## 5. AI-DLC との差(意図的)

| AI-DLC | 本リポジトリ | 理由 |
|---|---|---|
| 33 ステージ、11 scope | 5 stage、4 scope | 単独メンテナの学習環境。ステージ数ではなく「誰が受領証を書くか」を学ぶ |
| TypeScript エンジン + 17 hooks | bash 300 行 + hook 3 本追加 | 既存ハーネスの流儀(依存ゼロ、`bash -n`、ERR trap) |
| 自律モード(ladder prompt、swarm) | 無し。全 unit が HITL-3 以上 | 下げる動機が無い |
| sensor 機構 | `verify.sh` | 既にある |
| Learnings が `memory/project.md` に自動追記 | `/retro` が人間と決めて rules / hook に書く | 学びを機械に強制させる方(hook)を優先したい |
