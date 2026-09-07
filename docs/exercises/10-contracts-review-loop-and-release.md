# Exercise 10 — 契約テスト、レビューループ、出荷物の証明

- Phase: 8a
- 日付: 2026-09-07
- PR: phase8a/supply-chain-and-contracts

## 1. 導入したもの

| 種類 | 追加 | 何を保証するか | 配置 |
|---|---|---|---|
| 契約 | `apps/api/src/links/contracts.ts`(zod、consumer の期待)→ `contracts/*.schema.json`(JSON Schema 2020-12 を生成)。`contracts:check` で drift 検出 | 「api が期待する形」が 1 箇所にあり、生成物と一致していること | verify 全体・CI(ts) |
| 契約 | shortener(Go)/ enricher(Python)の **producer 側テスト** が `contracts/*.schema.json` で自分の応答を検証 | 応答の形を変えると **api を起動せずに** producer のテストが落ちる | verify(go / py)・CI |
| レビュー | `test-reviewer` subagent を実行し、重大 5 / 中 5 / 低 2 の指摘を得て対応 | 決定論的ツールが見ない「テストの弱さ」 | Agent(PR 前) |
| 出荷 | `release.yml`: タグ push で 4 image を GHCR へ。BuildKit provenance / SBOM、SLSA provenance attestation、CycloneDX SBOM attestation、push 前に Trivy image gate | 「どのソースからどのビルドで作られた image か」を検証できる(`gh attestation verify`) | タグ時のみ |

## 2. 契約テストが Exercise 09 の穴を塞いだか

Exercise 09: shortener の応答を `code` → `short` に変えると、producer のテスト(偶然)と実行時 warn 以外は何も気づかなかった。

今回の構成で同じ変更をすると:

| 層 | 結果 |
|---|---|
| shortener の `TestCreateResponseMatchesConsumerContract` | **FAIL**: `response violates the consumer contract: at '': missing property 'code'`(実測) |
| api の drift check | 変化なし(api 側の期待は変えていないので正しい) |
| api の単体テスト | 変化なし(fake) |

producer が「自分の応答は consumer の期待を満たすか」を、consumer が生成した JSON Schema で確認する。Pact のようなブローカーは要らない。
制約: consumer が 1 つ(api)だから成り立つ単純化。consumer が増えたら `contracts/<consumer>/` に分けるか、本物の consumer-driven contract testing に移る。

もう 1 つの副産物: zod スキーマを 1 箇所(`contracts.ts`)に集めたことで、`target` が URL 形式であることまで契約に含まれ、api 側の client テストの fixture(`target: "x"`)が契約違反として落ちた。**契約を厳密にすると、自分の fake も正直になる。**

## 3. test-reviewer subagent の実行結果

Phase 7 で定義した subagent を、直近 3 PR のテスト 6 ファイルに対して実行した(約 13 分、42 ツール呼び出し)。

| 重大度 | 指摘 | 対応 |
|---|---|---|
| 重大 | web client の `create(url, title)` の title 分岐が未検証、request body を一切見ていない | body を assert するテスト追加 |
| 重大 | web client の「2xx だが item 欠落」分岐が未検証 | 追加 |
| 重大 | `POST /links` の title 境界(空・空白・201 文字)が未検証(Stryker 生存 mutant と一致) | `it.each` に 3 行追加 |
| 重大 | `isPublicHost` の `172.20〜29`、IPv6 `fe80:` / `fc00::`、先頭アンカーが未検証 | 追加 → **本物のバグを発見**(下記) |
| 重大 | shortener の `/health` が未テスト(Docker HEALTHCHECK が依存) | 追加 |
| 中 | shortener の code 長さ違反と文字種違反の混同、`validateTarget` の 3 メッセージ未区別、client の code 境界、item の主要フィールド、list のエラー経路 | 全て追加 |
| 低 | e2e の重複保存シナリオ、Stryker mutant 33 の位置特定(要確認) | 未対応(記録のみ) |

### レビューが見つけたバグ

追加した「公開ホスト」ケース `10.example.net` が落ちた。`isPublicHost` は `/^10\./` 等の正規表現を **ホスト名にも** 適用しており、`10.example.net` や `192.168.example.com` のような正当なドメインを私設 IP として拒否していた。
修正: 私設レンジの判定は IPv4 リテラル(`^\d{1,3}(\.\d{1,3}){3}$`)にだけ適用し、IPv6 は zone id を除いて判定する。

- **同語反復でないテストを 1 本足すだけで、実装のバグが出る。** これは coverage でも Stryker でも(元のテストが偽陽性を検証していなかったので)出なかった。「境界値を足せ」という非決定的な助言が、決定論的な失敗に変換された瞬間。
- Stryker の score は url.ts で 79% → 77% に **下がった**。分岐が増えて mutant の母数が増えたため。score の絶対値より「どの mutant が生きているか」を読む方が有用。

## 4. Release workflow

まだタグを打っていないので **未実行**(意図的。次のセッションで `v0.1.0` を打って検証する)。設計:

1. `docker/build-push-action` に `provenance: mode=max` と `sbom: true` → image に BuildKit の attestation が同梱される。
2. push 後、digest に対して `trivy image`(HIGH 以上、修正版あり)→ 落ちたら release 失敗(PR 時と同じ基準)。
3. `actions/attest-build-provenance` で SLSA provenance を GitHub の attestation store と registry に記録。
4. Syft で CycloneDX SBOM → `actions/attest-sbom` で紐付け。
5. `gh attestation verify oci://ghcr.io/nkctkt/learn_harness/<name>@<digest> --repo nkctkt/learn_harness` で検証できる。

権限(`packages: write`、`id-token: write`、`attestations: write`)はこの workflow の job だけが持つ。PR の workflow には無い。

## 5. Dependabot PR の状態(triage の準備)

`#11`(actions 9 件の一括更新、SHA 付き)は CI 全通過だが `BLOCKED`。承認要件は 0 なので、残る要因は「会話の解決」か「unattributed changes への追加承認」ルール。Phase 8b で原因を特定し、bot PR の取り込み方針(auto-merge の可否、cooldown)を決める。docker base の major 更新(node 26、python 3.14、nginx 1.31)は Exercise 06 の image CVE の観点から中身を見て判断する。

## 6. 途中で踏んだこと

- **生成物を formatter にかけると drift になる。** Biome が `contracts/*.json` を整形し、`contracts:check` が「zod と一致しない」と報告した。生成物は formatter の対象から外す(gitignore ではなく、コミットはする)。
- JSON Schema バリデータ(Go)が `golang.org/x/text v0.14.0` を間接依存で引き込み、Trivy fs が HIGH(修正版あり)で止めた。`go get @latest` で解決。**テスト用の依存でも lockfile に入れば同じゲートを通る。**
- pyright strict と starlette の TestClient / jsonschema の型情報(部分的に Any)の相性が悪い。テストファイル単位で `reportUnknown*` を理由付きで緩めた。

## 7. Phase 8a で防げるようになった欠陥

| 欠陥 | Phase 7b | Phase 8a |
|---|---|---|
| producer の応答変更で consumer が壊れる | 実行時 warn のみ | producer のテストが CI で落ちる |
| consumer の期待(zod)と公開契約の乖離 | - | drift check で merge 不可 |
| テストの弱さ(境界値・分岐) | Stryker 週次 | + test-reviewer の助言 → 今回はバグ 1 件を検出 |
| 出荷 image の出所不明 | - | provenance / SBOM attestation(タグ時。未実行) |
