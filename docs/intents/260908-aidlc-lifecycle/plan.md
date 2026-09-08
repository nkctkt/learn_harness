# plan — 260908-aidlc-lifecycle

## 設計判断

- ADR-0001: ライフサイクルの記録と承認ゲートを bash + markdown で再実装する(AI-DLC のエンジンを採用しない)

## 分解(Units)

```yaml
units:
  - name: u1-intent-state-machine
    kind: library
    depends_on: []
  - name: u2-hooks-receipts-and-guard
    kind: library
    depends_on: [u1-intent-state-machine]
  - name: u3-verify-docs-stage-ci
    kind: packaging
    depends_on: [u1-intent-state-machine, u2-hooks-receipts-and-guard]
  - name: u4-skills-rules-agent
    kind: spec
    depends_on: [u1-intent-state-machine]
  - name: u5-docs-exercise-templates
    kind: spec
    depends_on: [u2-hooks-receipts-and-guard, u3-verify-docs-stage-ci, u4-skills-rules-agent]
```

| Unit | 触るパス | 触れる境界 | 大きさ |
|---|---|---|---|
| u1-intent-state-machine | `scripts/intent.sh`、`scripts/tests/intent.test.sh`、`docs/intents/README.md` | なし(docs 配下のみ) | M |
| u2-hooks-receipts-and-guard | `.claude/hooks/{record-human-turn,session-start,guard-plan-approval}.sh`、`guard-edit.sh`、`guard-bash.sh`、`.claude/settings.json`、`scripts/tests/hooks.test.sh` | ハーネス(HITL-4) | M |
| u3-verify-docs-stage-ci | `scripts/verify.sh`、`scripts/verify/docs.sh`、`.github/workflows/security.yml` | CI(HITL-4) | S |
| u4-skills-rules-agent | `.claude/skills/{intent,plan-units,adr,build-unit,create-pr,release,incident,retro}/SKILL.md`、`.claude/rules/*.md`、`.claude/agents/plan-reviewer.md`、`docs/adr/0001` | なし | M |
| u5-docs-exercise-templates | `docs/lifecycle.md`、`docs/exercises/12-*.md`、`docs/plan.md` §10、`docs/harness-architecture.md`、`README.md`、`AGENTS.md`、`templates/harness/**` | なし | M |

## 順序と walking skeleton

u1 が縦串: `intent.sh new → gate present → (hook が書く HUMAN_TURN) → gate approve → stage → unit → close → check` が一時ディレクトリで一周する(`intent.test.sh`)。
これが通るまで hook(u2)を書かない。理由: 受領証の意味(誰が書き、誰が読むか)が固まらないと hook の責務が決まらない。
u2 → u3 は依存順。u4 は u1 と並行可能だが、skill の手順は intent.sh のコマンド名に依存するので u1 の後。u5 は最後(全体が固まってから記録)。

## Definition of Done

- u1: `scripts/tests/intent.test.sh` 全件通過(作成 / 受領証無しの承認拒否 / 段階順序 / unit 遷移 / note / close / check の改竄 4 種)
- u2: `scripts/tests/hooks.test.sh` 全件通過(計画未承認の deny、記録ファイルの deny / ask、HUMAN_TURN の記録、承認後の allow、SessionStart の注入)。`bash -n` 全 hook
- u3: `scripts/verify.sh --only docs` が全体モードで tests を、`--changed` で intent 変更時のみ check を走らせる。`security.yml` の infra job が `--only infra,docs`
- u4: `scripts/tests/harness-shape.test.sh` 全件通過(各 SKILL.md の name / description、name とディレクトリ名の一致、各 rules の `paths:`、各 agent の name / description / tools)。plan-reviewer がこの plan.md に verdict を返す(助言。Exercise 12 §5 に記録)
- u5: Exercise 12 に「作る → 壊す → 検出 → 修正」が記録され、`harness-shape.test.sh`「template drift」が通り(同一であるべき 40 数ファイルの byte 一致)、`scripts/verify.sh` 全体が通る

## 検証計画

| AC | Unit | テスト / verify の段 |
|---|---|---|
| AC1 | u2 | `hooks.test.sh`「計画未承認: apps への Write → deny」 |
| AC2 | u1 | `intent.test.sh`「提示直後(HUMAN_TURN 無し)の承認は拒否」「古い HUMAN_TURN は再利用できない」 |
| AC3 | u1, u3 | `intent.test.sh`「check: …を検出」×5、`security.yml` infra job |
| AC4 | u2 | `hooks.test.sh`「SessionStart が active intent を注入する」 |
| AC5 | u4 | `harness-shape.test.sh`「skill frontmatter」「rule paths」「agent frontmatter」 |
| AC6 | u5 | この記録の `audit.log` に GATE_PRESENTED → HUMAN_TURN → GATE_APPROVED が並び、CI の docs 段が緑 |

## ハーネスへの影響

- 追加: PreToolUse(guard-plan-approval)、SessionStart、UserPromptSubmit、PostToolUse(AskUserQuestion)の hook。`verify.sh` の `docs` 段。
- 変更: guard-edit(記録ファイルの deny)、guard-bash(受領証操作の ask、計画未承認の deny)、`security.yml` infra job のコマンド。
- 全て HITL-4。理由は PR 本文に書く。
