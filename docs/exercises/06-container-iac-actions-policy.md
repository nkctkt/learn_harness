# Exercise 06 — Container / IaC / Actions / Policy: コードが動く環境の定義を検査する

- Phase: 5
- 日付: 2026-09-07
- PR: phase5/container-iac-actions-policy

## 1. 導入したもの

| 種類 | ツール | 対象 | 何を検出するか | 検出しないもの |
|---|---|---|---|---|
| Lint | Hadolint | Dockerfile | ベストプラクティス違反(latest タグ、apt の未固定、`ENV` の秘密、shell 形式の CMD) | image の中身の CVE |
| Lint | actionlint | workflows | 構文・式の型エラー、shellcheck、**信頼できない入力の直接展開** | 権限設計、pin |
| Misconfig | Trivy config | Dockerfile / Terraform / compose | 汎用の危険設定 DB(root 実行、port 22、公開 S3、全開 SG、暗号化なし) | 組織固有の決め事 |
| Image scan | Trivy image(CI) | ビルド済み image | OS パッケージと言語依存の既知 CVE(修正版あり、HIGH 以上) | 設定不備(config が見る) |
| Workflow security | zizmor | workflows | `pull_request_target`、template injection、unpinned、credential 残留(artipacked)、権限過剰 | 構文エラー(actionlint が見る) |
| Policy as Code | Conftest / Rego(`policies/rego/`) | workflows / package.json / Terraform | **うちの決め事**: SHA 固定必須、`pull_request_target` 禁止、`permissions` 必須、完全固定バージョン、install hook 禁止、公開 ACL 禁止、443 以外の公開 SG 禁止、IAM `*` 禁止 | 汎用の危険設定(Trivy が見る) |
| Egress | harden-runner(audit) | CI ジョブ | 想定外の宛先への通信(まず観測、Phase 8 で block) | - |
| 整合 | terraform fmt / validate | Terraform | 整形、型・参照の整合 | セキュリティ |

ツール導入は composite action(`.github/actions/setup-infra-tools`)で **バージョンと sha256 を固定**して行う。タグ参照の action もリモートスクリプトの直接実行も使わない。

## 2. ベースライン(自分のファイル)で見つかったもの

ツールを入れた直後、演習の前に自分のファイルで 15 件以上が出た。

| ツール | 指摘 | 対処 |
|---|---|---|
| Trivy config | `AVD-AWS-0104` CRITICAL: api SG の egress が 0.0.0.0/0 | enricher の外部取得に必要なので **理由付きで受容**(`#trivy:ignore:AVD-AWS-0104` を該当ブロック直上に) |
| Hadolint | DL3066(非数値 UID)×2、DL3025(HEALTHCHECK の shell 形式) | `USER 10001`、JSON 形式に修正 |
| zizmor | `artipacked` MEDIUM ×10: checkout が credential を残す | 全 checkout に `persist-credentials: false` |
| zizmor | `template-injection` info: `echo '${{ toJSON(needs) }}'` | `env: NEEDS: ${{ toJSON(needs) }}` 経由に |
| actionlint | SC2086: `exit ${status:-0}` の未引用 | 引用 |
| Semgrep p/default(Phase 4)| pnpm の `minimumReleaseAge` / `trustPolicy` / `blockExoticSubdeps` 未設定 | 設定 |

「受容」と「修正」の判断基準: 修正できるものは修正する。要件上外せないもの(egress)は、**スキャナが理由を表示できる形**で受容し、無言の除外(`.trivyignore` に ID だけ)にはしない。

## 3. 意図的欠陥と検出結果

### Dockerfile(`ubuntu:latest`、`ENV API_TOKEN`、apt 未固定、port 22、shell 形式 CMD、root)

| ツール | 検出 |
|---|---|
| Hadolint | DL3007 latest、DL3064 ENV の秘密、DL3008 apt 未固定、DL3015 / DL3009、DL3025 CMD |
| Trivy config | DS-0001 タグなし、DS-0002 root、DS-0004 port 22、DS-0029 no-install-recommends、**DS-0031 CRITICAL** ENV の秘密 |

同じ Dockerfile に対して Hadolint は 6 件、Trivy は 5 件で、重なるのは 3 件。Hadolint は「書き方」、Trivy は「危険性」に寄っている。

### Terraform(`acl = "public-read"`、SSH 0.0.0.0/0、IAM `*`/`*`)

| ツール | 検出 |
|---|---|
| Trivy config | 8 件(HIGH 7) |
| Conftest(自作 Rego) | 公開 ACL、public_access_block 欠如、22 番の公開、(IAM `*` はテストで確認済み) |
| terraform validate | **通る**(構文的には正しい) |

### Workflow(`pull_request_target` + `write-all` + `@v4` + `@main` + タイトルの直接展開)

| ツール | 検出 |
|---|---|
| actionlint | `github.event.pull_request.title` の直接展開(1 件) |
| zizmor | dangerous-triggers、template-injection、unpinned-uses ×2、artipacked(4 high) |
| Conftest(自作 Rego) | 未固定 ×2、直接展開、write-all、`pull_request_target`(修正後) |

### package.json(`^1.3.0`、`github:` 依存、`postinstall`)

Conftest が 3 件全て。lint も型検査も `package.json` の意味は見ない。**規約(AGENTS.md「完全固定」)を機械検査に変換した**のがこのルール。

## 4. Rego で踏んだ落とし穴

1. **conftest の hcl2 パーサは同名ブロックを配列にする。** `resource.aws_s3_bucket.cache` は `[{...}]`。最初のルールはオブジェクト前提で、実ファイルに対して誤った失敗を出した(テストは通っていた。**テスト入力の形がパーサの出力と違っていた**)。`conftest parse` で実際の形を確認してからテストを書く。
2. **YAML 1.1 では `on:` キーが真偽値 `true` になり、conftest の入力では文字列キー `"true"` になる。** `input.on.pull_request_target` は `.github/workflows/*.yml` に対して一度も発火せず、演習で初めて気づいた(zizmor は検出していた)。`input.on` と `input[true]` の両方を見るように直し、`true` キーのテストを追加した。**ルールのテストが通ることと、実ファイルで動くことは別**。
3. **Rego の unit test は「検出されるべき」と「されるべきでない」を対で書く。** Semgrep の `ruleid:` / `ok:` と同じ考え方。

## 5. 層の配置

| 段 | 所要 | 配置 |
|---|---|---|
| hadolint / actionlint / conftest | 1 秒未満 | verify 全体・CI(infra job) |
| zizmor(uv tool run) | 数秒 | 同上 |
| terraform init / validate | 初回 30 秒(provider 取得)、以後数秒 | 同上 |
| trivy config(repo 全体) | 数秒 | 同上 |
| trivy image ×3 | 各 20〜40 秒 | CI の docker job のみ(ビルド済み image が必要) |

Hook 層には入れない。Dockerfile や Terraform の編集は頻度が低く、全体 verify(Stop hook / CI)で十分。

## 6. Phase 5 で防げるようになった欠陥

| 欠陥 | Phase 4 | Phase 5 |
|---|---|---|
| root 実行・latest・秘密入り ENV の Dockerfile | 検出手段なし | Hadolint + Trivy config で merge 不可 |
| image 内の既知 CVE | 検出手段なし | CI の Trivy image で merge 不可 |
| 公開 S3 / 全開 SG / IAM ワイルドカード | 検出手段なし | Trivy config(汎用)+ Rego(組織固有)で merge 不可 |
| SHA 未固定 action、`pull_request_target`、write-all | Dependabot のみ | zizmor + Rego で merge 不可 |
| CI からの想定外 egress | 検出手段なし | harden-runner が観測(block は Phase 8) |
| `^` 付き依存、`postinstall` | 規約のみ | Rego で merge 不可 |

## 7. 見送ったもの・残課題

- **Claude Code の sandbox(ネットワーク allowlist、credential deny)は導入していない。** pnpm / uv / Docker / gh が使う宛先を洗い出してから入れないと、開発が止まる。harden-runner の audit ログ(CI 側の egress 一覧)を参考に Phase 8 で設計する。
- guard-bash は `rm -rf` を含む自己テストコマンドを正しく拒否した(4 件目の「誤検知ではない検知」)。一時ファイルは個別に消す。
- Terraform の plan-json に対するポリシー(実際の差分を見る)は、apply 先が無いので扱わない。

## 8. 追記: CI の Trivy image スキャンが 3 image 全てで落ちた

ローカルでは `trivy config`(Dockerfile の書き方)しか回していなかった。CI でビルド済み image を `trivy image` にかけると、**我々の lockfile には無い** 既知 CVE が出た。

| image | 検出 | 由来 | 対処 |
|---|---|---|---|
| api(node:24-alpine) | libcrypto3 HIGH ×1、npm 同梱の tar / brace-expansion / ip-address HIGH ×3 | ベース image の OS パッケージと、Node 公式 image に同梱される npm の依存 | `apk upgrade`、実行時に不要な npm / yarn を削除 |
| web(nginx-unprivileged:1.27-alpine) | HIGH 30 / CRITICAL 2(openssl、c-ares、libexpat …) | 1.27 系のベースが alpine 3.21 で古い | 1.29-alpine に更新 + `apk upgrade`(root に戻して実行し、`USER 101` に戻す) |
| enricher(python:3.13-slim) | setuptools HIGH ×1(+1) | Python 公式 image 同梱の pip / setuptools | 実行時に不要な pip / setuptools / wheel を削除 |

学び:

- **`trivy fs`(lockfile)と `trivy image`(ビルド済み)は見ている物が違う。** ベース image 由来の CVE は lockfile に現れない。両方が要る。
- **ベース image は「依存」である。** Dependabot の docker ecosystem が同時に nginx 1.31 / node 26 / python 3.14 の PR を開いた(#6〜#9)。cooldown 7 日は効いているが、major 更新なので中身を見てから取り込む。
- **実行時に不要な物は image から外す**(npm、pip、setuptools)。CVE の数が減るだけでなく、侵入後にできることも減る。
- CI の shellcheck は `A && B || C` を SC2015 で拒否した(ローカルの actionlint は通した。同梱 shellcheck のバージョン差)。`if ... then exit 1; fi` に書き換えた。**同じツール名でも CI とローカルでバージョンを揃えないと結果が揃わない**(Exercise 05 の trivy と同じ教訓)。
