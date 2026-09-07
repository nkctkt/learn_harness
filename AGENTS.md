# AGENTS.md — Reading Shelf

全てのコーディングエージェント向けの共通指示。200 行以内に保つ。
手順は `.claude/skills/`、領域別ルールは `.claude/rules/` に置く(Phase 1 以降)。
設計判断と計画は `docs/plan.md` を参照。

## プロジェクト概要

- 目的: Harness Engineering の学習。アプリより品質ゲートの理解が優先。
- 構成: `apps/web`(React + Vite)、`apps/api`(Hono)、`services/enricher`(FastAPI)、
  `services/shortener`(Go、短縮 URL)、`infra/`(Docker / Terraform)、`policies/`(Semgrep / Rego)
- パッケージ管理: JS は pnpm workspace(依存は完全固定)、Python は uv(`uv.lock`)、Go は modules(`go.sum`)

## コマンド

- JS 依存: `pnpm install --frozen-lockfile`
- API 開発: `pnpm --filter @shelf/api dev`(http://localhost:3000)
- Web 開発: `pnpm --filter @shelf/web dev`(`/api/*` を API へ proxy)
- Enricher: `cd services/enricher && uv run uvicorn enricher.main:app --port 8000`
- Shortener: `cd services/shortener && go run ./cmd/shortener`(http://localhost:8081)
- DB: `docker compose -f infra/docker/compose.yaml up -d`
- 型検査: `pnpm -r typecheck`
- 全検証(CI と同一): `scripts/verify.sh`。段を限定するなら `--only ts,py,go,sec,infra`。変更分だけなら `--changed`
- セキュリティ段のみ: `scripts/verify.sh --only sec`(Semgrep 自作ルール + Trivy)

## 規約

- 入力は境界(HTTP ハンドラ)で zod / pydantic により検証する。`any` と `# type: ignore` を使わない。
- 秘密情報をコード・テスト・ログ・コミットに書かない。設定は環境変数経由。
- 新しいサービス・言語の追加は `/new-service` skill のチェックリストに従う(ゲートの漏れを防ぐ)。
- 依存追加は `/add-dependency` skill の手順に従う(実在・保守・ライセンス・脆弱性・公開日)。バージョンは完全固定。
- 外部 URL を取得するコードは `enricher.fetch.fetch_html`(名前解決後の IP で検証)経由のみ。api から直接 fetch しない。
- SQL は Drizzle のクエリビルダか `sql\`...${x}\``。`sql.raw` に補間・連結を渡さない(Semgrep が拒否する)。
- 意図的な欠陥を作る演習では、ファイル先頭に `// EXERCISE:` / `# EXERCISE:` コメントを付け、
  `docs/exercises/` に記録してから修正する。

## テスト方針

- 変更したロジックには単体テストを追加する。実装の写しではなく振る舞いを検証する。
- 検証コマンドが通るまで完了扱いにしない。テストの skip / 無効化で回避しない。

## Git / PR

- ブランチ名: `phase<N>/<slug>` または `fix/<slug>`。`main` へ直接 push しない。
- コミットは Conventional Commits。1 コミット = 1 つの意味のある変更。
- PR には「何を守るゲートを追加/変更したか」と「意図的欠陥の検出結果」を書く。

## やってはいけないこと

- `.env*`、`~/.ssh`、`~/.aws` を読まない・書かない。
- `rm -rf`、`git push --force`、`git reset --hard`、`terraform apply` を実行しない。
- `.github/workflows/**`、`.claude/settings.json`、`policies/**` を変更する時は、その理由を PR に明記する。
