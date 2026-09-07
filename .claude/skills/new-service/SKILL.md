---
name: new-service
description: monorepo に新しいサービス(新しい言語を含む)を追加し、ハーネス(verify.sh / hooks / CI / Docker / ポリシー)に乗せる手順。Phase 6 で Go を追加した実績から抽出。
argument-hint: "<path> <language: ts|py|go> [<purpose>]"
---

# 新しいサービスをハーネスに乗せる

「動くコード」を書くのは半分。残り半分は **既存のゲート全部を、その言語・そのサービスに対して有効にする** こと。
1 つでも漏れると、その領域だけ Phase 0 の状態(何も守られていない)に戻る。

## チェックリスト(順番どおりに)

1. **骨格と疎通**
   - `services/<name>/`(または `apps/<name>/`)に最小の `/health` を持つサービスを作る。
   - 依存は完全固定。install スクリプトを走らせない(pnpm `allowBuilds`、uv、`go mod`)。
2. **言語ツールチェーン(ローカル)**
   - format / lint / type / test / vuln の 5 種を揃える。既存: TS = Biome + tsc + typescript-eslint + Vitest、Py = Ruff + basedpyright + pytest、Go = gofmt + go vet + golangci-lint + `go test -race` + govulncheck。
   - 設定ファイルはサービス直下(`.golangci.yml`、`pyproject.toml`、`vitest.config.ts`)。抑制には理由を必須にする(`nolintlint`、`PGH003`)。
3. **verify.sh に段を追加**
   - `scripts/verify/<lang>.sh` を `_lib.sh` の `step` で書く。`--files`(編集ファイル / 所属パッケージのみ、テスト無し)、`--changed`(変更パッケージ + テスト)、全体(+ vuln)の 3 モードを実装する。
   - `scripts/verify.sh` の `run_lang` に追加。`--only <lang>` で単独実行できることを確認。
   - 未導入ツールは **skip を明示して exit 0**(CI では必ず入っている前提)。
4. **Hooks**
   - `.claude/hooks/post-edit-check.sh` の拡張子リストに追加(PostToolUse)。Stop hook は `--changed` なので自動で対象になる。
   - `guard-edit.sh` に守るべきパス(lockfile、生成物)があれば追加。
5. **CI**
   - `ci.yml` の path filter に `<lang>` を追加し、言語 job を作る(SHA 固定の setup action、ツールのバージョンをローカルと揃える、実行は `scripts/verify.sh --only <lang>`)。
   - `ci-ok` の `needs` に追加。**required check(Rulesets)は触らない**(`ci-ok` 1 本のまま)。
6. **Docker**
   - multi-stage、非 root(数値 UID)、`--ignore-scripts` 相当、シェル不要なら distroless。
   - `ci.yml` の docker matrix、`infra/docker/compose.yaml`、`scripts/verify/infra.sh` の `DOCKERFILES` に追加。
   - ローカルで `hadolint` と `trivy image` を通してから push(ベース image の CVE はここでしか見えない)。
7. **ポリシー / ドキュメント**
   - 依存宣言のポリシー(Rego)が言語固有なら追加(`package_json.rego` に相当するもの)。
   - `AGENTS.md` のコマンド一覧に開発・検証コマンドを追記。
   - `docs/exercises/NN-*.md` に「その言語で意図的に壊す → どのゲートが拾うか」を記録する。

## 所要時間の目安

Go(3 言語目)は上記全部でエージェント作業の壁時計 約 5 分、人間が手でやれば 1〜2 時間が目安(Exercise 07)。
どこかで詰まったら、それはハーネス側の一般化不足なので `docs/plan.md` の課題に書く。
