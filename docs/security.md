# Security — SAST / SCA / Secrets / Container / IaC / Supply chain

セキュリティ系ゲートの設計と、意図的欠陥で確認した検出範囲。各行の根拠は `docs/exercises/` の番号。

## 1. 脅威と対応表

| 脅威(AI 駆動開発で特に高い) | 対策 | 層 | 演習 |
|---|---|---|---|
| 秘密情報のコピペ(AI 支援コミットで 2 倍) | guard-secrets(書込前)→ gitleaks(staged / 全履歴)→ Trivy secret → push protection | Hook / pre-commit / CI / サーバ | 03, 05 |
| 文字列連結 SQL | Drizzle クエリビルダ + Semgrep `sql.raw` 補間禁止 | CI | 04, 05 |
| SSRF(ユーザー URL の取得) | 静的判定(api `isPublicHost`)+ 名前解決後の IP 判定(enricher `resolve_public_url`)+ リダイレクト毎の再検証 + Semgrep taint | 実装 + CI | 05, 10 |
| 既知 CVE を持つ依存 | Trivy fs / dependency-review(PR)、Trivy ドリフト(Nightly)、govulncheck(到達可能性) | CI / Nightly | 05, 07 |
| 公開直後の悪性版、slopsquatting | pnpm `minimumReleaseAge` 7 日、Dependabot cooldown、`/add-dependency` の実在確認、Rego 完全固定 | install / 週次 / Agent | 05 |
| install スクリプトの任意コード実行 | pnpm `allowBuilds`、image の `--ignore-scripts`、Rego で postinstall 禁止 | install / build / CI | 00, 04, 06 |
| ベース image の CVE | Trivy image(docker job / release)、`apk upgrade`、不要物(npm / pip)の削除、distroless | CI / release | 06, 07 |
| 危険な Dockerfile(root、latest、ENV 秘密) | Hadolint、Trivy config | CI | 06 |
| 危険な IaC(公開 S3、全開 SG、IAM `*`) | Trivy config、Rego | CI | 06 |
| CI の乗っ取り(tag 差し替え、`pull_request_target`、injection、credential 残留) | SHA 固定(Rego / zizmor / Dependabot)、Rego、actionlint、`persist-credentials: false`、harden-runner | CI | 06 |
| 出荷 image の出所不明 | BuildKit provenance / SBOM、SLSA attestation、CycloneDX attestation | release | 10 |
| Agent の破壊的操作 | permissions.deny + guard-bash(force push、rm -rf、terraform apply、DROP) | Hook | 04 |
| ハーネス自体の無断改変 | guard-edit(ask)、CODEOWNERS、Rulesets | Hook / サーバ | 04, 10 |

## 2. SAST

### Semgrep(PR 時、gate)

- 自作ルール(`policies/semgrep/`、unit test 付き):
  - `shelf.drizzle-sql-raw-interpolation`: `sql.raw` への補間・連結。
  - `shelf.postgres-js-unsafe`: `.unsafe()`。
  - `shelf.ts-ssrf-unvalidated-fetch`(taint): Hono の `c.req.*` → `fetch`。sanitizer は `isPublicHost` / `assertPublicUrl`。
  - `shelf.py-ssrf-unvalidated-request`(taint): FastAPI ハンドラの `req.url` → httpx / requests。sanitizer は `resolve_public_url` / `fetch_html`。
- `p/default`: 汎用。pnpm の供給網設定不備(`minimumReleaseAge` / `trustPolicy` / `blockExoticSubdeps`)や provider の静的資格情報を指摘した。
- 学び: taint の sanitizer は「値がそこを通って返る」形でないと消えない。`if (!ok) return` は sanitizer にならない(Ex.05)。設計指針としても「検証済みの値を別変数にする」のは正しい。
- 隠しディレクトリ(`.semgrep/`)はスキャン対象外になる。検体は意図的に悪いコードなので、スキャンと Biome から除外する。

### CodeQL(Nightly、report)

- js-ts / python / actions、`security-extended`。関数境界を越えるデータフロー。数分かかるので PR には載せない。

## 3. SCA

| ツール | 対象 | 判定 | 配置 |
|---|---|---|---|
| Trivy fs | pnpm-lock / uv.lock / go.sum | 既知 CVE、HIGH 以上、修正版あり | verify sec / CI gate / Nightly(MEDIUM 以上 report) |
| dependency-review-action | PR で増えた依存 | HIGH 以上 + ライセンス allowlist | PR |
| govulncheck | Go の呼び出しグラフ | 到達可能な脆弱関数のみ | verify go / CI |
| Trivy image | ビルド済み image(OS パッケージ + 言語依存) | HIGH 以上、修正版あり | docker job / release |
| Dependabot | 週次更新 | cooldown 7 日 / major 30 日 | PR(owner approve 必須) |

学び:

- `trivy fs` と `trivy image` は別物。ベース image の CVE(node 同梱 npm、python 同梱 setuptools、古い alpine)は image でしか出ない(Ex.06)。
- govulncheck と Trivy は同じ CVE でも判定が違う(到達可能性 vs lockfile)。ノイズを減らすなら前者、見逃しを減らすなら後者(Ex.07)。
- テスト用依存(JSON Schema バリデータ)の間接依存でも同じゲートを通る(Ex.10)。
- ライセンス allowlist は「許容できるが載っていないもの」を止める。止まった時に理由をコメントで残す(CC-BY-4.0、BSD-2-Clause-Views)(Ex.08)。

## 4. Secrets(4 層)

| 層 | ツール | 範囲 | 特性 |
|---|---|---|---|
| Agent の書込前 | `guard-secrets.sh`(PreToolUse) | Edit/Write の内容、`git commit` の staged 差分 | 依存ゼロの自前パターン。行内 `allow-secret: <理由>` で逃がす |
| commit 前 | gitleaks(lefthook) | staged | エントロピー閾値あり(規則的な値は見逃す) |
| CI | gitleaks(全履歴)、Trivy secret | 全履歴 / fs | Trivy はエントロピーを見ない(規則的な値も拾う) |
| サーバ | GitHub push protection | push | プロバイダパターン |

同じ「github-pat」パターンでも、gitleaks は規則的な架空値を見逃し、Trivy は CRITICAL にした(Ex.05)。検出範囲のズレが層を重ねる理由。

## 5. Container

| ツール | 見るもの | 実測 |
|---|---|---|
| Hadolint | Dockerfile の書き方(latest、apt 未固定、ENV の秘密、shell 形式 CMD、非数値 UID) | まずい Dockerfile で 6 件 |
| Trivy config | 危険設定(root、port 22、HEALTHCHECK 無し、no-install-recommends) | 同じファイルで 5 件、Hadolint と重なるのは 3 件 |
| Trivy image | 中身の CVE | node:24-alpine で 4 件、nginx 1.27-alpine で 32 件、python slim で 2 件(Ex.06)|

方針: multi-stage、非 root(数値 UID)、`--ignore-scripts`、`apk upgrade`、実行時に不要な npm / pip / setuptools を削除、Go は distroless static(15 MB、0 件)。HEALTHCHECK はシェルが無ければバイナリ自身の `-healthcheck` モードで(Ex.07)。

## 6. IaC

- Terraform は `validate` と scan のみ(apply しない。guard-bash が deny、provider に資格情報を置かない)。
- Trivy config(汎用)+ Rego(組織固有: 公開 ACL 禁止、public access block 必須、443 以外の 0.0.0.0/0 禁止、IAM `*`/`*` 禁止)。
- 受容は理由付きで(`#trivy:ignore:AVD-AWS-0104` を該当ブロック直上に)。無言の `.trivyignore` にしない。

## 7. Supply chain

| 対策 | 実装 |
|---|---|
| lockfile | 完全固定(`saveExact`、Rego)、`--frozen-lockfile` / `--locked` |
| cooldown | pnpm `minimumReleaseAge: 10080`、`trustPolicy: no-downgrade`、`blockExoticSubdeps`、Dependabot cooldown |
| install スクリプト | pnpm `allowBuilds`(esbuild / lefthook / ssh2 系を false)、image は `--ignore-scripts` |
| Actions | SHA 固定 + Rego + zizmor + Dependabot、composite action で sha256 検証 |
| 出荷物 | `release.yml`: BuildKit `provenance: mode=max` + `sbom: true`、`attest-build-provenance`、Syft CycloneDX + `attest-sbom`。検証は `gh attestation verify oci://<image>@<digest> --repo nkctkt/learn_harness` |
| 監査 | OpenSSF Scorecard(Nightly)、harden-runner audit |

## 8. Agent 固有の境界

- `permissions.deny`(15 件)と `guard-bash.sh` の二重化。deny は設定編集で緩められるが hook は別ファイル。
- `guard-edit.sh`: `.env*`、lockfile、適用済み migration は deny。ハーネス自体は ask(HITL-4)。
- fail-closed: hook 自身の実行時エラーは deny を返す。構文エラーは block(全ツール停止)になるので `bash -n` を pre-commit に。
- sandbox は未導入。設計は `docs/harness-architecture.md` §6。

## 9. 検出できないもの(正直な限界)

- 認可ロジックの穴(このユーザーがこのリソースを見てよいか)。テストとレビューでしか守れない。
- 未知の脆弱性(0-day)。
- 上流メンテナの悪意(cooldown は時間を稼ぐだけ)。
- ビジネスロジックの誤り。
- Agent が hook を回避する経路の全て(heredoc、`settings.json` の書き換え)。最終防衛線は CI + Rulesets。
