# Exercise 07 — Go の追加: 3 言語目をハーネスに乗せるのに何が要るか

- Phase: 6
- 日付: 2026-09-07
- PR: phase6/go-shortener

## 1. 計測: 3 言語目を乗せるのにかかった時間

| 区間 | 時刻 | 内容 |
|---|---|---|
| 開始 | 11:07:51 | ブランチ作成、Go ツールチェーン確認、govulncheck 導入 |
| 骨格 | 〜11:09 | `services/shortener`(Store / Handler / main)、テスト、`.golangci.yml`、`go test -race` 通過 |
| ハーネス | 〜11:11 | `scripts/verify/go.sh`、verify.sh 配線、PostToolUse hook の拡張子、CI go job、docker matrix、compose、infra の Dockerfile 一覧 |
| 検証 | 〜11:12 | `verify.sh --only go` 全通過、image build 15 MB、trivy image クリーン、コンテナで疎通 |
| 演習・記録 | 〜11:15 | 意図的欠陥 5 種、この文書 |

**実装からゲート全通過まで、壁時計で約 5 分**(エージェント作業。人間が同じチェックリストを手でやれば 1〜2 時間が目安)。
かかった時間より重要なのは、**触ったファイルの一覧がそのまま `/new-service` skill のチェックリストになった**こと。1 つでも忘れるとその領域は Phase 0 に戻る。

触ったファイル: `scripts/verify/go.sh`、`scripts/verify.sh`、`.claude/hooks/post-edit-check.sh`、`.github/workflows/ci.yml`(filter / job / matrix / needs)、`infra/docker/compose.yaml`、`scripts/verify/infra.sh`、`AGENTS.md`、`services/shortener/**`。

## 2. Go ツールチェーンの責務

| ツール | 責務 | 演習で拾ったもの |
|---|---|---|
| gofmt / goimports | 整形 | - |
| go vet | 「ほぼ確実にバグ」(printf の型不一致、到達不能コード、コピーされる Mutex) | `Sprintf("%d", string)` |
| golangci-lint(staticcheck / errcheck / gosec / revive …) | 「たぶんバグ」「危険 API」「規約」 | 捨てられた error、`exec.Command` に変数、`math/rand`、exported のコメント |
| `go test -race` | **実行時**のデータ競合。静的には分からない | Mutex 無しカウンタ |
| govulncheck | 依存の既知脆弱性のうち **到達可能な関数**だけ | (下記) |
| trivy image | image 全体 | distroless なので 0 件 |

## 3. 意図的欠陥と検出結果

| # | 欠陥 | go vet | go test | go test -race | golangci-lint |
|---|---|---|---|---|---|
| 1 | Mutex 無しで 8 goroutine が `c.n++` | ✘ | **ok**(たまたま合う) | ✔ `WARNING: DATA RACE` ×2 | ✘ |
| 2 | `fmt.Sprintf("code=%d", code string)` | ✔ printf | ✔(`go test` は vet の一部を内蔵) | - | ✔ govet |
| 3 | `os.Remove(path)` の error 無視 | ✘ | ✘ | ✘ | ✔ errcheck |
| 4 | `exec.Command("sh", "-c", arg)` / `math/rand` | ✘ | ✘ | ✘ | ✔ gosec G204 / G404 |
| 5 | exported にコメント無し | ✘ | ✘ | ✘ | ✔ revive |

観察:

- **#1 は `-race` 以外の全てを素通りした。** テストは通り、vet も lint も静かだった。Go でテストに `-race` を付けない CI は、並行バグに対して何も守っていない。`go.sh` は `--changed` と全体モードで常に `-race` を付ける(数倍遅くなるが、このリポジトリの規模では 1 秒台)。
- **#2 は `go test` を止めた。** `go test` は vet の一部(printf 等)を内蔵しており、vet 違反があるとテスト自体が build failed になる。最初の演習ではこのせいで #1 の race テストが走らず、ファイルを分けて再実行した。**1 つの検体に複数の欠陥を混ぜると、早い層が遅い層の観測を隠す。**
- **govulncheck は「到達可能」を見る。** `golang.org/x/text@v0.3.7`(CVE-2022-32149)を入れて脆弱関数 `ParseAcceptLanguage` を呼ぶ関数を置いたが、その関数がどこからも呼ばれていない(unexported かつ未使用)ため「No vulnerabilities found」になり、注記として「packages you import に 1 件」と出た。lockfile を見る Trivy なら即 HIGH で止まる。**同じ CVE でも SCA(lockfile)と govulncheck(呼び出しグラフ)では判定が違う。** ノイズを減らしたいなら govulncheck、見逃しを減らしたいなら Trivy、両方入れて役割を分ける。
- **gosec G710(オープンリダイレクト)は本番コードで出た。** 短縮 URL サービスは「保存済み URL へ転送する」のが仕様なので、転送前に再検証した上で `//nolint:gosec // 理由` で抑制した。`nolintlint` の `require-explanation` により理由の無い抑制は lint エラーになる。

## 4. image

- `golang:1.27-alpine` でビルドし、`gcr.io/distroless/static-debian12:nonroot` に静的バイナリだけを置く。15 MB、シェル無し、uid 65532。
- Trivy image は 0 件(OS パッケージが存在しない)。api / web / enricher(Phase 5 で HIGH 多数)との差は、ベース image に何を持ち込むかの差そのもの。
- Hadolint は初回から 0 件。

## 5. Phase 6 で防げるようになった欠陥

| 欠陥 | Phase 5 | Phase 6 |
|---|---|---|
| Go のデータ競合 | (Go 無し) | `-race` で CI merge 不可 |
| Go の危険 API・error 無視 | - | golangci-lint で merge 不可 |
| Go の到達可能な脆弱依存 | - | govulncheck(全体モード)で merge 不可、Trivy fs が go.sum も見る |
| 新言語追加時のゲート漏れ | 記憶頼み | `/new-service` チェックリスト(強制ではない。Phase 8 でテンプレート化) |

## 6. 残課題

- `services/shortener` はメモリ実装。api から呼ぶ配線と DB 実装は Phase 7 以降。
- CI の golangci-lint-action は導入のみに使い実行は `verify.sh` に統一した。action 側のキャッシュを活かすには `args` で直接実行する方が速いが、「同じスクリプト」原則を優先した。
- reusable workflow 化は Phase 8 の `templates/` 切り出しと同時に行う。
