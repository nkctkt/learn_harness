# learn_harness — Harness Engineering 学習プロジェクト

AI Coding Agent 時代のコード品質保証(Quality Gate / CI / Claude Code Harness)を、
小さな Web アプリ「Reading Shelf」を実際に構築しながら体系的に学ぶためのリポジトリ。

- 計画と設計判断: [docs/plan.md](docs/plan.md)
- 演習記録(意図的欠陥 → 検出 → 原因 → 修正): `docs/exercises/`
- 元になった調査: `../ai_driven_development/`

## 構成(予定)

| パス | 内容 |
|---|---|
| `apps/web` | React + Vite フロントエンド |
| `apps/api` | Hono + Drizzle API |
| `services/enricher` | FastAPI: URL メタデータ取得 |
| `services/shortener` | Go: 短縮 URL(Phase 6) |
| `infra/` | Docker / Terraform |
| `scripts/verify.sh` | hooks と CI が共有する検証スクリプト |
| `templates/` | 最終成果物の再利用テンプレート |
