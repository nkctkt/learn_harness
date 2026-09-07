# Exercise 11 — 一般化: テンプレート、release の検証、bot PR の triage

- Phase: 8b
- 日付: 2026-09-07
- PR: phase8b/templates-and-docs

## 1. 作ったもの

| 成果物 | 内容 |
|---|---|
| `docs/quality-engineering.md` | 7 つの問いによる分類、各ゲートの責務と実測で分かった境界、配置表、Agent の失敗から逆算した優先度、入れなかったもの |
| `docs/harness-architecture.md` | L1〜L10 の責務、各層の実体と学び、HITL 対応、責務分離の原則(計画からの修正 7 点)、既知の穴、sandbox 設計 |
| `docs/ci-design.md` | workflow 分割、job 構成、並列化・キャッシュ、Rulesets、Actions のセキュリティ、gate / report 分離、bot PR、計測 |
| `docs/security.md` | 脅威 × 対策 × 層 × 演習の対応表、SAST / SCA / Secrets / Container / IaC / Supply chain、検出できないもの |
| `templates/harness/`(copier) | verify(targets.sh 以外はそのまま)、hooks / skills / agents / settings、workflows 4 本 + composite action、rulesets、Rego / Semgrep、lefthook、gitleaks、ツール設定、AGENTS.md 雛形、sandbox 設計例 |
| `scripts/verify/targets.sh` | プロジェクト固有の値(パッケージ、モジュール、Dockerfile、Terraform)をここだけに集約。他の verify スクリプトを project-agnostic にした |
| `README.md` | 読む順番、構成、動かし方、**hook が全滅した時の復旧手順** |

## 2. テンプレートの検証

`copier copy --defaults --data languages=[ts,py] --data ts_packages=apps/api --data py_projects=services/api` で生成:

- 49 ファイル、`.jinja` の残り 0。`targets.sh` / `CODEOWNERS` / `AGENTS.md` / ruleset の承認数が正しく埋まる。
- 生成物の shell 15 本は `bash -n` 通過、Rego の unit test 19 件通過、`actionlint` 通過。
- 設計上の判断: **アプリの雛形は入れない**(ハーネスとアプリは寿命が違う)。**ci.yml の path filter と言語 job は生成後に人間が合わせる**(README に手順)。完全な自動化より「何を埋めるべきかが明示されている」ことを優先した。

踏んだこと:

- copier.yml の `help:` に「例: apps/api」と書くと `: ` が YAML の mapping と解釈されて壊れる。`choices` のラベルも同様。**設定ファイルの中の日本語説明にも YAML の文法が効く。**
- テンプレートに `biome.json` を同梱すると、ルートの Biome が「nested root configuration」で落ちる。テンプレートツリー(`templates/`)は Biome / ESLint / knip / Semgrep / Docker context の全てから除外する必要があった(生成物と同じ扱い)。
- テンプレート内の `.claude/skills/` を Claude Code がスコープ付き skill として認識した(`templates/harness/template:add-dependency`)。害は無いが、ネストした `.claude/` は自動検出されることを知っておく。

## 3. Release の検証(`v0.1.0`)

タグを push し、`release.yml` が 4 image を並列に GHCR へ push、Trivy image gate 通過、attestation を記録した(全 job success)。

```
gh attestation verify oci://ghcr.io/nkctkt/learn_harness/api:v0.1.0 --repo nkctkt/learn_harness
  → exit 0(SLSA provenance v1)
gh attestation verify ... --predicate-type https://cyclonedx.org/bom
  → exit 0(CycloneDX SBOM)
```

4 image とも同じ。これで「この image は nkctkt/learn_harness のこのコミットから、この workflow で作られた」ことと「中に何が入っているか」を、レジストリの外(GitHub の attestation store)から検証できる。

- 権限(`packages` / `id-token` / `attestations` の write)は release の job だけが持つ。PR の workflow には無い。
- image gate は PR 時と同じ基準(HIGH 以上、修正版あり)。release で初めて出る CVE は無い設計。

## 4. Dependabot PR の triage

| 状態 | 原因 | 方針 |
|---|---|---|
| actions 一括更新(#11 → 作り直されて #17)が全 check 緑なのに BLOCKED | Rulesets の **Code Owner レビュー必須**。owner 自身が author の PR は免除されるが、bot が author の PR は owner の approve が要る | **意図どおり**(ハーネス自体を bot が変える PR に人間を挟む)。owner が diff(SHA と `# vN` コメントの整合)を見て approve → merge |
| docker base の major(node 26、python 3.14、nginx 1.31) | cooldown 7 日は通過。major は 30 日 | Exercise 06 の image CVE の観点では新しい方が有利。ランタイム互換(node 26 の npm 同梱、python 3.14 の依存 wheel)を確認してから 1 つずつ |
| `@types/node` 24 → 26 | minor / patch グループに入らない major | api は 26 系、web は 24 系と揃っていない。26 に揃える |

auto-merge は入れない。Dependabot は上位版が出ると PR を作り直すので、番号ではなく `gh pr list --author app/dependabot` で追う。

## 5. sandbox(設計のみ)

`templates/harness/template/.claude/sandbox.disabled.json` に allowlist 案(npm / PyPI / Go proxy / GitHub / GHCR / Docker Hub / gcr / semgrep / playwright / anthropic)と credential deny(`~/.aws`、`~/.ssh`、`~/.config/gh`)を置いた。有効化しなかった理由は、宛先を実測せずに入れると開発が止まるため。手順は `docs/harness-architecture.md` §6。

## 6. Phase 8b で得たもの

| 目的(計画 §1) | 到達 |
|---|---|
| 品質チェックの地図を持つ | `docs/quality-engineering.md`(7 つの問い × 責務 × 配置 × 実測の境界) |
| 信頼境界を設計できる | `docs/harness-architecture.md`(層ごとの速度 / 信頼度 / バイパス可能性と、計画から修正した原則 7 点) |
| 再利用可能なテンプレートに落とす | `templates/harness`(copier、49 ファイル、生成物を検証済み) |

## 7. 残課題(次のプロジェクトで)

- テンプレートを **実際に別リポジトリへ適用して**、README の「適用後にやること」の抜けを埋める(適用時間を計測する)。
- `ci.yml` の言語 job を `targets.sh` から自動生成する(今は人間が合わせる)。
- sandbox の有効化(宛先の実測から)。
- harden-runner を `block` に(StepSecurity の insights で宛先を確定してから)。
- 契約が複数 consumer になった時の `contracts/<consumer>/` 分割。
