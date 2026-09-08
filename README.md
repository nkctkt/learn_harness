# learn_harness — Harness Engineering 学習プロジェクト

AI Coding Agent 時代のコード品質保証(Quality Gate / CI / Claude Code Harness)を、
小さな Web アプリ「Reading Shelf」を実際に構築しながら体系的に学んだ記録と、その成果物。

## 読む順番

1. [docs/plan.md](docs/plan.md) — 計画、設計判断、Phase 表、既知の穴
2. [docs/quality-engineering.md](docs/quality-engineering.md) — 何を・なぜ・どこで検査するか(実測で修正した体系)
3. [docs/harness-architecture.md](docs/harness-architecture.md) — CLAUDE.md / Skills / Hooks / pre-commit / CI / Rulesets の責務分離
4. [docs/ci-design.md](docs/ci-design.md) — Job 構成、並列化、キャッシュ、required checks、merge policy
5. [docs/security.md](docs/security.md) — SAST / SCA / Secrets / Container / IaC / Supply chain
6. [docs/lifecycle.md](docs/lifecycle.md) — 開発ライフサイクルの各タスク(intent → plan → build → PR → release / incident → retro)と、支援 / 強制する要素(AI-DLC 参照)
7. `docs/exercises/00〜12` — 意図的欠陥 → 検出 → 原因 → 修正 の記録(本文の根拠)
8. [templates/README.md](templates/README.md) — 新規プロジェクトへの適用手順(copier)
9. [docs/improvement-plan.md](docs/improvement-plan.md) — 「生産性と品質の両立」の観点での診断と改善計画(Phase 10 の入力)

元になった調査: `../ai_driven_development/`(2026-09-03)。Phase 9 のライフサイクル層は AWS の AI-DLC(`../aidlc-workflows`)を参照(`docs/plan.md` §12)。

## 構成

| パス | 内容 |
|---|---|
| `apps/web` | React + Vite(フォーム、一覧、Playwright smoke) |
| `apps/api` | Hono + Drizzle + Postgres(`POST/GET /links`、enricher / shortener を呼ぶ) |
| `services/enricher` | FastAPI(SSRF 対策付き URL 取得、OG 解析) |
| `services/shortener` | Go(短縮 URL、クリック集計、distroless) |
| `contracts/` | api の期待(zod)から生成した JSON Schema。producer 側のテストが読む |
| `scripts/verify.sh` | hooks / pre-commit / CI が共有する検証。`--files` / `--changed` / 全体、`--only ts,py,go,sec,infra`。対象は `scripts/verify/targets.sh` |
| `.claude/` | settings(deny / hooks)、hooks(guard-* / post-edit-check / stop-verify / record-human-turn / guard-plan-approval / session-start)、rules(領域別)、skills(`/add-dependency` `/new-service` `/fix-ci` + ライフサイクル 8 本)、agents(`test-reviewer` `plan-reviewer`) |
| `scripts/intent.sh`、`docs/intents/` | 変更 1 件ごとの記録(intent / plan / state / audit / memory / retro)と承認ゲート。`docs/adr/` は設計判断 |
| `.github/` | workflows(ci / security / nightly / release)、rulesets as code、CODEOWNERS、dependabot |
| `policies/` | Semgrep 自作ルール、Rego(workflows / package.json / Terraform) |
| `infra/` | compose(4 サービス)、Terraform(validate と scan のみ) |
| `templates/` | 上記ハーネスの copier テンプレート |

## 動かす

```
pnpm install --frozen-lockfile
docker compose -f infra/docker/compose.yaml up --build      # web:8080 api:3000 enricher:8000 shortener:8081
scripts/verify.sh                                            # CI と同じ全検証(約 35 秒 + Docker)
```

## ハーネスが自分を止めた時の復旧手順(人間向け)

Claude Code の PreToolUse hook が構文エラーになると、bash は exit 2 を返し、Claude Code はそれを **block** と解釈する。
`guard-bash.sh` と `guard-edit.sh` が同時に壊れると、Agent は Bash も Edit/Write も使えず **自分では直せない**(Exercise 04 で実際に起きた)。

```
# 1) どの hook が壊れているか
for f in .claude/hooks/*.sh; do bash -n "$f" || echo "BROKEN: $f"; done

# 2) 直前のコミット版に戻す(未コミットの変更が要るなら手で直す)
git restore .claude/hooks/guard-bash.sh .claude/hooks/guard-edit.sh

# 3) それでも止まる時は hooks を一時的に外す(settings.json を退避)
mv .claude/settings.json .claude/settings.json.off   # 復旧後に必ず戻す
```

再発防止として pre-commit(lefthook)が `bash -n` を実行し、`.claude/**` の変更は CODEOWNERS の承認が要る。
