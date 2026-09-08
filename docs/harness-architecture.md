# Harness Architecture — CLAUDE.md / Skills / Hooks / pre-commit / CI の責務分離

Agent が「どう書くか」を助ける層と、Repository が「何を通すか」を強制する層を分ける。
根拠となる事故・演習は `docs/exercises/` の番号で参照する。

## 1. 層モデル(調査 4.2 の L0〜L11 を実装で検証した版)

```
                          速度    信頼度  バイパス  役割
 L1 AGENTS.md / CLAUDE.md 即時    低      可       「何を守るか」の宣言。短く(52 行)。
 L2 Skills                即時    低      可       「どうやるか」の手順。長くてよい。
 L3 Hooks / permissions   秒      中      可*      境界(deny / ask)と fast feedback。
 L4 Sandbox               -       中      可*      (未導入。設計は §6)
    Subagents             分      低〜中   可       意味レベルのレビュー。block にしない。
 ── ここまでは Agent への「支援」と「境界」。品質保証ではない ──
 L5 pre-commit(lefthook)  秒      中      可       人間の git commit 経路。
 L6 Rulesets              -       最高    不可     CI を「不可」にするのはこれ。
 L7 CI                    分      高      不可**   全体の決定的検証。
 L9 Policy as Code(Rego)  秒      高      不可     組織の決め事を実行可能に。
 L10 Human approval       -       -       不可     CODEOWNERS(ハーネス自体、bot の PR)。
    Nightly / Release     時間    高      不可     重いもの、出荷物の証明。
 * managed settings で補強可能(本リポジトリの範囲外)  ** Rulesets の required check であるとき
```

## 2. 各層の責務と、このリポジトリでの実体

### L1 AGENTS.md / CLAUDE.md / rules — 「知っているべき事実と短いルール」

- `AGENTS.md`(63 行): 構成、コマンド、規約、ライフサイクル、テスト方針、Git 作法、禁止事項。`CLAUDE.md` は `@AGENTS.md` + Claude 固有 3 行。
- `.claude/rules/*.md`(Ph.9、7 本): `paths:` で領域(api / web / enricher / shortener / infra / harness / intents)ごとに自動で読まれる事実。AI-DLC の memory 層(org → project → phase)を Claude Code の仕組みで実現したもの。AGENTS.md を 200 行以内に保つための逃がし先。
- **書かないもの**: 手順(→ Skills)、linter で強制できること、長い説明。
- **限界**: request に過ぎない。「テストの skip 禁止」と書いても Agent は skip し得る。守らせたいことは Hook(L3)か CI(L7)に変換する。

### L2 Skills — 「承認済みの手順」

| Skill | 何を標準化するか | 由来 |
|---|---|---|
| `/add-dependency` | 実在・保守・ライセンス・脆弱性・公開日の確認 → 完全固定で追加 | slopsquatting、cooldown(Ex.05) |
| `/new-service` | 言語・サービス追加時に触るべきファイルのチェックリスト | Go 追加で触った 8 ファイル(Ex.07) |
| `/fix-ci` | CI 失敗ログの読み方、再現、禁止事項(skip / 閾値緩和) | Ex.01, 03, 05, 06, 07 の失敗パターン |
| `/intent` `/plan-units` `/adr` `/build-unit` `/create-pr` `/release` `/incident` `/retro` | ライフサイクルの各タスクの手順(記録 → ゲート → 実装 → PR → 運用 → 振り返り)。ゲートは 2 択で提示してターンを終える | AI-DLC の stage(Phase 9、`docs/lifecycle.md`) |

Skill は「手順を短くする」ものであって「手順を強制する」ものではない。強制は L3 / L7 で行う(例: `/add-dependency` を通らない `pnpm add` を止めるのは Rego の完全固定ルールと cooldown)。

### L3 Hooks / permissions — 「必ず起きること」と「できないこと」

| Hook | イベント | 責務 | 学び |
|---|---|---|---|
| `guard-secrets.sh`(PR #2) | PreToolUse(Edit/Write/Bash) | 秘密情報・PII を **書く前・commit する前** に拒否 | 4 層の secret 検出の最前線(Ex.03) |
| `guard-bash.sh` | PreToolUse(Bash) | 破壊的 git、rm -rf、infra 変更、hook 回避、リモートスクリプト実行を deny。ハーネス改変は ask | 文字列全体を見るので、コミットメッセージやコメント内の禁止語句にも反応する(Ex.04) |
| `guard-edit.sh` | PreToolUse(Edit/Write) | `.env*`、lockfile、適用済み migration を deny。ハーネス自体は ask(HITL-4) | fail-closed(ERR trap)。 |
| `post-edit-check.sh` | PostToolUse(Edit/Write) | 編集ファイルだけ `verify.sh --fix --files` | block できない。heredoc は素通り(Ex.01) |
| `stop-verify.sh` | Stop | `verify.sh --changed` が通るまで完了を block | 「テストした」を「テストが通った」に変える層(Ex.03) |
| `permissions.deny`(15 件) | - | hook と二重化 | 設定を緩められても hook が残る |
| `record-human-turn.sh`(Ph.9) | UserPromptSubmit / PostToolUse(AskUserQuestion) | 人間の在席を `audit.log` に書く(HUMAN_TURN)。`intent.sh gate approve` はこれが無いと拒否 | 受領証は Agent が発行できないものにする(AI-DLC) |
| `guard-plan-approval.sh`(Ph.9) | PreToolUse(Edit/Write) | active intent の計画が未承認なら `apps/ services/ packages/ infra/ contracts/` を deny | 「計画が先、コードは後」を指示ではなく hook で守る |
| `session-start.sh`(Ph.9) | SessionStart | intent の状態と hook の `bash -n` 結果を additionalContext で注入 | 状態は Git のファイルに置き、開始時に読み直す |

**最大の教訓(Ex.04)**: hook の構文エラーは exit 2 = block で、**Agent の全ツールが止まり自己修復できない**。対策は pre-commit の `bash -n`、hook 変更を CODEOWNERS 承認に、README の復旧手順。

### Subagents — 「決定論的ツールが見られないもの」

- `test-reviewer`: テストが実装を壊した時に落ちるかを読む。13 分でバグ 1 件を発見(Ex.10)。
- 助言であってゲートではない。指摘を **テストに変換して初めて** 決定論的になる。
- `plan-reviewer`(Ph.9): 計画承認ゲートの前に plan.md を敵対的に読む(AC の取りこぼし、walking skeleton、検証不能な DoD、未申告の信頼境界)。READY / NOT-READY を返すが承認は人間。

### L5 pre-commit(lefthook)— 人間の commit 経路

- staged ファイルの `verify.sh --files`、gitleaks(導入端末のみ)、shell 構文、Conventional Commits。
- Claude Code の hook は Agent のツール呼び出しにしか反応しない。人間が `git commit` を打つ経路はここ。`--no-verify` で回避できる(guard-bash は Agent からの回避を拒否する)。

### L6 Rulesets — CI を強制力に変える

- `main` への直接 push 禁止、required checks `ci-ok` + `security-ok`、線形履歴、会話の解決必須、Code Owner レビュー必須。
- Rulesets as code(`.github/rulesets/*.json` + `scripts/github/apply-rulesets.sh`)。
- **required check は集約 job(`ci-ok` / `security-ok`)だけ**を登録する。言語 job が増減しても Rulesets を触らず、path filter で skip された job も正しく成功扱いになる。
- 副作用(Ex.07): code scanning の PR コメントは「会話の解決必須」を通じて **LOW でも merge を止める**。PR 時の SARIF を HIGH 以上に限定した。
- 副作用(Ex.10): Code Owner レビュー必須により、**bot(Dependabot)の PR は owner の approve が要る**。owner 自身が author の PR は免除される。ハーネス自体の変更に人間を挟む意図どおり。

### L7 CI — 全体の決定的検証

`docs/ci-design.md` を参照。要点: 同じ `verify.sh`、path filter、SHA 固定、harden-runner、gate と report の分離。

### L9 Policy as Code(Conftest / Rego)

- workflows(SHA 固定、`pull_request_target` 禁止、permissions 必須、untrusted 展開禁止)、package.json(完全固定、install hook 禁止)、Terraform(公開 ACL / 全開 SG / IAM `*` 禁止)。
- ルール自体に unit test(`conftest verify`)。テスト入力はパーサの出力形に合わせる(hcl2 は配列、YAML の `on` は `"true"` キー)(Ex.06)。

### L10 Human approval

- CODEOWNERS: `.github/`、`.claude/`、`policies/`、`infra/`、`scripts/verify*` は owner 承認(HITL-4)。
- HITL レベルの実装対応:

| Level | 内容 | 実装 |
|---|---|---|
| HITL-1 | AI + 自動テスト | feature branch、Stop hook |
| HITL-2 | + セキュリティ検査 | required checks(`security-ok`) |
| HITL-3 | + 人間承認 | Rulesets(単独メンテナのため approvals 0。テンプレートでは 1 を推奨) |
| HITL-4 | + Platform / Security 承認 | CODEOWNERS、guard-edit の ask、bot PR の approve |
| HITL-5 | 人間のみ | `terraform apply`、DROP、force push を deny |

## 3. 責務分離の原則(計画時の 4 層からの修正点)

1. **「Agent 側 = 非決定的、CI 側 = 決定的」ではない。** Hook の lint も決定的。分かれ目は **バイパスできるか**。
2. **CLAUDE.md に手順を書かない。指示で守らせたいことは Hook に変換する。** 変換できないもの(設計の妥当性)だけが指示に残る。
3. **Hook は品質ゲートではなく「CI で落ちるまでの時間を前倒しするもの」。** Hook を素通りした変更(heredoc、他ツール)は CI が受け止める。
4. **Hook 自身の品質を検証するゲートが要る**(`bash -n`、CODEOWNERS)。Hook は決定論的だが無謬ではない。
5. **CI の出力を Agent に戻す経路まで含めて初めてループが閉じる**(`/fix-ci`、job summary、SARIF)。
6. **レポートとゲートは分ける。** 同じツールでも severity と出力先を変える(Trivy の table gate + SARIF report)。レポートが PR コメントになるとゲート化する。
7. **Agent が自分を止めてしまう設計は、回復経路まで設計する**(Ex.04)。

## 4. 同じ検査が層ごとに違う範囲で走る(意図的な冗長)

| 検査 | Hook | pre-commit | CI | Nightly / サーバ |
|---|---|---|---|---|
| format / lint / 型 | 編集ファイル + パッケージ | staged | 全体 | - |
| テスト | 変更パッケージ(Stop) | - | 全体 + 結合 + 契約 | mutation(週次) |
| secret | 書込前(guard-secrets) | staged(gitleaks) | 全履歴(gitleaks)+ fs(Trivy) | push protection |
| 依存脆弱性 | - | - | Trivy fs + dependency-review + image | Trivy ドリフト(毎日) |
| SAST | - | - | Semgrep | CodeQL |
| workflow / IaC / policy | - | shell 構文 | actionlint / zizmor / Trivy config / Conftest | Scorecard |

## 5. 既知の穴(全て `docs/plan.md` §10 に記録)

- PostToolUse は `Edit|Write` にしか反応しない(Bash の heredoc は素通り)→ Stop hook と CI で受ける。
- `.claude/settings.json` を編集すれば hook を消せる → guard-edit の ask + CODEOWNERS。それでも hooks 配列ごと消されれば消える → 最終防衛線は CI と Rulesets。
- hook の構文エラーで Agent が完全停止する → `bash -n`、復旧手順(README)。
- guard-bash が文字列リテラルにも反応する(誤検知 3 件)→ `git commit -F`、Write ツール。
- 承認の受領証(HUMAN_TURN)と guard-plan-approval はローカル層(Ph.9)→ CI の `intent.sh check` と PR での `docs/intents/` diff レビュー。新しい subagent はセッション再起動まで呼べない。

## 6. Sandbox(未導入。導入時の設計)

Claude Code の sandbox は Bash とその子プロセスをファイルシステム・ネットワーク境界で隔離する。導入していない理由は、pnpm(registry.npmjs.org)、uv(pypi.org、files.pythonhosted.org)、Go(proxy.golang.org、sum.golang.org)、Docker(registry-1.docker.io、ghcr.io、gcr.io、mirror.gcr.io)、gh(api.github.com、github.com)、Trivy(ghcr.io の DB)、Semgrep registry、Playwright(playwright.azureedge.net)と、許可すべき宛先が多く、洗い出さずに有効化すると開発が止まるため。

導入手順(テンプレートに `sandbox.disabled.json` として同梱):

1. harden-runner の audit ログ(CI 側の egress 一覧)と、ローカルでの 1 日分の宛先を集める。
2. `sandbox.enabled: true`、`network.allowedDomains` に宛先、`credentials.files` で `~/.aws` / `~/.ssh` を deny、`allowUnixSockets` に docker.sock は **入れない**(ホスト奪取経路)。
3. `failIfUnavailable: true` で「sandbox 無しで動いてしまう」ことを防ぐ。
4. 1 週間は `excludedCommands` を使わずに運用し、止まったコマンドを記録してから allowlist を調整する。

## 7. テンプレートへの一般化

`templates/harness/`(copier)に、プロジェクト固有でない部分(verify.sh の骨格、hooks、skills、agents、workflows、rulesets、policies、lefthook、gitleaks、Biome / ESLint / knip / dependency-cruiser の設定)を切り出した。適用手順と、適用直後に人間が埋めるべき項目は `templates/README.md` を参照。
