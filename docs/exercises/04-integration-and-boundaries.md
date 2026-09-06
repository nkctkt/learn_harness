# Exercise 04 — 結合・ビルド・境界: 単体テストで再現できないものと、Agent を止める層

- Phase: 3
- 日付: 2026-09-06
- PR: phase3/integration-and-boundaries

## 1. 導入したもの

| 層 | 追加 | 何を保証するか | 保証しないもの |
|---|---|---|---|
| コード | Drizzle スキーマ(`links`)、`LinkRepository`、`POST/GET /links`、`createApp(repo)` の依存注入 | HTTP 層を DB 無しで単体テストできる構造 | - |
| 結合テスト | Testcontainers で本物の Postgres 17 を起動し、マイグレーション・unique 制約・SQL メタ文字を検証 | インメモリ実装では再現できない DB の振る舞い | 本番 DB との差(拡張、権限) |
| Build | 3 つの Dockerfile(multi-stage、非 root、`--ignore-scripts`)、compose での E2E 疎通 | 「main がビルドできる」こと | image の脆弱性(Phase 5) |
| Boundaries | `permissions.deny`(15 件)、`guard-bash.sh`(破壊的 git / rm -rf / terraform apply / `--no-verify` / `curl \| sh` を deny、ハーネス改変を ask)、`guard-edit.sh`(`.env*` / lockfile / 適用済み migration を deny、ハーネス自体を ask) | Agent が「できないこと」 | Agent が「やるべきでないが可能なこと」(意味的判断) |
| CI | docker build job(matrix 3 image、GHA cache、push 無し) | image が壊れた PR を merge しない | - |
| pre-commit | `bash -n` で shell script の構文検査 | hook 自身の構文エラーを commit しない | ロジックの誤り |

## 2. 単体テストと結合テストの責務差(実測)

| 検証したいこと | 単体(インメモリ repo) | 結合(Testcontainers) |
|---|---|---|
| 400 の入力検証、正規化、非公開ホスト拒否 | ✔ 33 件、120ms | (重複するので書かない) |
| マイグレーションが適用できる | ✘ 再現不能 | ✔ |
| `href` の unique 制約 | ✘ インメモリ実装は制約を持たない | ✔(drizzle が `Failed query:` で包むので `cause` を見る必要があった) |
| `' OR 1=1; DROP TABLE links; --` を含む URL を保存してもテーブルが残る | ✘ SQL が無い | ✔ 6 秒(コンテナ起動込み) |

- 結合テストは `INTEGRATION=1` の時だけ含め、`verify.sh --changed`(Stop hook)では走らせない。Docker 必須かつ数秒かかるので Hook 層には重すぎる。全体モード(CI / `test:coverage`)で必ず走る。
- SQLi のテストは「Drizzle のクエリビルダを使っている限り安全」の確認であって、文字列連結クエリを **書いてしまった時に検出する** 仕組みではない。それは Phase 4 の Semgrep(`sql.raw` + テンプレート補間のパターン)の責務。**テストは書いた経路しか守らない。**

## 3. 境界(Boundaries)の自己テスト結果

`guard-bash.sh`:

| コマンド | 決定 |
|---|---|
| `git push --force origin main` / `git push -f` / `git reset --hard` | deny |
| `git commit --no-verify` / `LEFTHOOK=0 git commit` | deny |
| `curl ... \| sh` / `terraform apply` / `rm -rf node_modules` | deny |
| `sed -i ... .github/workflows/ci.yml` | **ask**(HITL-4: 人間の確認) |
| `git push origin phase3/x` / `echo ok` | allow |

`guard-edit.sh`:

| パス | 決定 |
|---|---|
| `.env`, `apps/api/.env.local` | deny |
| `.env.example` | allow(プレースホルダの置き場) |
| `pnpm-lock.yaml` | deny(コマンド経由でのみ更新) |
| `apps/api/drizzle/*.sql` | deny(generate で新規作成) |
| `.github/workflows/ci.yml` | ask |
| `src/ok.ts` | allow |

`permissions.deny` と hook を二重化している理由: deny ルールは `settings.json` の編集で消せるが、hook は別ファイルなので片方が緩められても残る。ただし `settings.json` の hooks 配列自体を消されれば両方消えるので、最終的な保護は CODEOWNERS(`.claude/**` の変更に人間の承認)。

## 4. 事故: hook のバグで Agent が完全停止した

fail-closed にしようとして `trap '... \'...\' ...' ERR` と書いた。単一引用符の中で `\'` はエスケープにならず、**両 hook が構文エラー**になった。

- bash は構文エラーで exit 2 を返す。Claude Code は PreToolUse の exit 2 を **block** と解釈する。
- `guard-bash.sh` は全 Bash を、`guard-edit.sh` は全 Edit / Write を block した。**Agent 自身が hook を修復する手段が無くなった**(修復には Bash か Write が要る)。
- 回復は人間が端末で `sed -i '' '/^trap /d'` を打つまで不可能だった。

学び:

1. **hook は決定論的だが、hook 自身の品質は誰も保証していなかった。** `bash -n` を pre-commit に追加した。hook を触る PR は CODEOWNERS で人間が見る。
2. **fail-closed は正しい方針だが、実装は単純に。** 関数 `on_err` を定義して `trap on_err ERR` と書く。ネストした引用は書かない。
3. **hook のテストケースをコマンド文字列に埋め込まない。** `--no-verify` を含む自己テストコマンドが hook 自身に拒否された(文字列リテラルにも反応する既知の誤検知)。ケースはファイルに置く。
4. **Agent が自分を止めてしまう設計は、回復経路まで含めて設計する。** 今回は人間が横にいたから 1 分で直ったが、無人運用なら停止したまま。テンプレートには「hook が全滅した時の復旧手順」を README に書く。

## 5. Docker まわりの学び

- **root の `prepare`(`lefthook install`)が image build 内でも走って失敗した。** image では devDependencies が無いので lefthook が見つからない。`--ignore-scripts` を付けるのが正解で、供給網的にも「image build 中に依存の任意コードを走らせない」に一致する。
- **pnpm 11 は install 時に "Verifying lockfile against supply-chain policies" を出す。** lockfile の整合性検証が標準になっている。Phase 4 で内容を確認する。
- image サイズ: web 76MB(nginx-unprivileged)、api 264MB、enricher 264MB。api は tsx で TS を直接実行しているので、Phase 5 で build して JS だけ載せる形に変え、サイズと攻撃面を減らす余地がある。
- zsh では `set -- $t` が単語分割しない。Bash ツールの既定シェルが zsh であることを忘れていた。

## 6. compose での E2E 疎通

`docker compose up db api` → `POST /links` → `GET /links` → `down -v`。結果は本文末尾の実行ログ参照(成功なら 201 と一覧、非公開ホストは 400)。

## 7. Phase 3 で防げるようになった欠陥

| 欠陥 | Phase 2 | Phase 3 |
|---|---|---|
| DB 制約と実装の不一致 | 検出手段なし | 結合テストで検出 |
| ビルドできない main | 検出手段なし | CI の docker job で merge 不可 |
| `.env` の読み書き、`git push --force`、`rm -rf` | 規約のみ | permissions.deny + hook で拒否 |
| ハーネス自体の無断改変 | 規約のみ | hook が ask、CODEOWNERS で承認必須 |
| 文字列連結 SQL の混入 | 検出手段なし | **まだ検出手段なし**(Phase 4 Semgrep) |
| image の脆弱性・非推奨設定 | 検出手段なし | **まだ検出手段なし**(Phase 5 Trivy / Hadolint) |

## 8. 見送ったもの

- Playwright smoke は Phase 7(E2E)へ移動。web が API を叩くだけの現状では、compose の curl 疎通と同じことを 10 倍のコストでやることになる。UI にフォームが付いてから入れる。

## 9. 実行ログ(compose E2E)

```
GET  /health                      → {"status":"ok","service":"api"}
POST /links {url: "https://Example.com/docs#intro", title}
                                  → 201 {"item":{"id":1,"href":"https://example.com/docs",...}}
POST /links {url: "https://example.com/docs"}
                                  → 200(同じ id=1 を返す。重複しない)
POST /links {url: "http://169.254.169.254/latest"}
                                  → 400 {"error":"host is not public"}
GET  /links                       → {"items":[{"id":1,...}]}
```

最初の 2 回は失敗した。原因は (1) Phase 0 の `tsx watch` が port 3000 を掴んだままだった、(2) image が tsx を `node --import tsx` で使っていたが `--prod` install には無く `ERR_MODULE_NOT_FOUND`、(3) `compose up` に `--build` を付けず古い image を使った。(2) は「開発時に動く」と「image で動く」が別物である典型で、tsc でビルドした JS を実行する形に直した(devDependencies を image に入れない)。
