# Exercise 02 — Secret guard: 秘密情報・個人情報を「書き込む前」に止める

- Phase: 1(追加)
- 日付: 2026-09-05
- 目的: Exercise 00 で「手で打つコマンドすら存在しない」と記録した秘密情報の混入を、Agent 側の最速の層で止める。

## 1. 何を作ったか

`.claude/hooks/guard-secrets.sh` を **PreToolUse** hook として `.claude/settings.json` に登録した(matcher: `Edit|Write|MultiEdit|Bash`)。

| 発火点 | 検査対象 | 結果 |
|---|---|---|
| Edit / Write / MultiEdit | 書き込もうとしている内容と、ファイル名 | 該当すれば exit 2 で **書き込み自体を拒否** |
| Bash(`git commit` を含むコマンド) | staged 差分の追加行と、staged ファイル名。`-a` なら未 staged も | 該当すれば exit 2 で **コミットを拒否** |

Skills(指示)ではなく hook にした理由: 指示は Agent が「読んで従う」もので、忘れる・読み飛ばす・別 Agent には届かない。
hook は harness が実行するので、Agent の判断とは無関係に毎回同じ結果になる(plan §4「指示で守らせたいことは可能な限り Hook に変換する」)。
Phase 1 の `post-edit-check.sh` は PostToolUse なので **書き込んだ後にしか** 言えないが、秘密情報は一度でもディスクに書かれると
その後の `git add -A` で拾われうるため、PreToolUse で書き込み前に止める。

## 2. 検出できるもの・できないもの

検出できる(1 行単位の正規表現):

- 既知フォーマットの鍵: AWS access key(`AKIA…`)、AWS secret、GitHub `ghp_…` / `github_pat_…`、Anthropic `sk-ant-…`、OpenAI `sk-…`、Slack `xox?-…`、Google `AIza…`、`-----BEGIN … PRIVATE KEY-----`、JWT
- 汎用代入: `password = "…"`、`API_KEY: "…"` のように **引用符付きで 8 文字以上** の値
- 資格情報入り URL: `postgres://user:pass@host` <!-- allow-secret: 演習の例。実在しない値 -->
- 個人情報: メールアドレス、携帯電話番号(`0[789]0-xxxx-xxxx`)
- 置いてはいけないファイル名: `.env`(`.env.example` は除く)、`*.pem` `*.key` `id_rsa*` `*.tfstate` `credentials.json` `.npmrc` `.netrc` など

検出できない(=この hook だけでは守れない):

- 未知フォーマットの鍵、`a + b` に分割した鍵、base64 や hex で包んだ鍵
- 引用符無しの代入(`POSTGRES_PASSWORD: shelf`)。compose.yaml のローカル用ダミー値を通すための意図的な穴
- 氏名・住所・固定電話・マイナンバー等の個人情報(誤検知が多すぎるため対象外)
- hook を通らない経路: `git commit` を人間が端末から打つ、`cat > file` のような Bash によるファイル書き込み(Bash は commit 時にだけ検査する)
- Hook は `.claude/settings.json` を書き換えれば無効化できる(バイパス可能な層)

だからこれは「最速の層」であって「最後の層」ではない。plan のゲート配置表どおり、pre-commit と CI の gitleaks(Phase 2、lefthook と同時)、
サーバ側の GitHub push protection(Phase 0 残作業)を重ねて初めてゲートになる。

誤検知の逃がし方は 1 つだけ: 該当行に `allow-secret: <理由>` を書く。ファイル単位・パターン単位の抑制は用意していない。
理由を同じ行に書かせることで、レビューで「なぜ許したか」が diff に残る。

## 3. 意図的に壊す → 検出 → 修正

hook に渡る JSON を手で作って呼び出し、28 ケースを確認した(本物の鍵は一切使っていない。AWS 鍵は公式ドキュメントのサンプル)。

| ケース | 期待 | 結果 |
|---|---|---|
| `Write` で `AKIAIOSFODNN7EXAMPLE` を含む ts | 拒否 | 拒否 | <!-- allow-secret: 演習の例。実在しない値 -->
| 同上、行末に `allow-secret: …` | 許可 | 許可 |
| `Edit` で `sk-ant-…` / `ghp_…` / 秘密鍵ヘッダ / JWT | 拒否 | 拒否 |
| `MultiEdit` の 2 つ目の edit に Slack token | 拒否 | 拒否 |
| `password = "hunter2hunter2"` | 拒否 | 拒否 | <!-- allow-secret: 演習の例。実在しない値 -->
| `password = "<your_password>"`、`API_KEY=changeme` | 許可 | 許可 |
| `postgres://app:s3cretpass@db/x` | 拒否 | 拒否 | <!-- allow-secret: 演習の例。実在しない値 -->
| `POSTGRES_PASSWORD: shelf`(compose のダミー) | 許可 | 許可 |
| `taro.yamada@gmail.com` | 拒否 | 拒否 | <!-- allow-secret: 演習の例。実在しない値 -->
| `user@example.com`、`noreply@anthropic.com` | 許可 | 許可 |
| `.env` / `infra/id_rsa` への Write | 拒否 | 拒否 |
| `.env.example` への Write | 許可 | 許可 |
| `ls -la` / staged 無しの `git commit` | 許可 | 許可 |
| 鍵入りファイルを `git add` 後の `git commit -m` | 拒否 | 拒否 |
| `cd /tmp && git -c user.name=x commit -m` | 拒否 | 拒否(初版は見逃した。下記) |
| 鍵入りファイルが未 staged で `git commit -m` | 許可 | 許可(staged に無いものは commit されない) |
| 同上で `git commit -am` | 拒否 | 拒否 |
| `.env` を `git add -f` 後の `git commit` | 拒否 | 拒否 |
| リポジトリの全追跡ファイルを Write に流す | 許可 | `docs/exercises/00-baseline.md` のサンプル鍵だけ拒否 → 当該行に `allow-secret` を付けて解消 |

初版で見つかった欠陥 2 つ:

1. **`printf … | block` と書くと `exit 2` がパイプのサブシェルで閉じ、hook 本体は exit 0 で終わる。** 検出メッセージは stderr に出るのに書き込みは通ってしまう。
   「ログには出ているが止まっていない」は hook で最も危険な壊れ方なので、テストは必ず **終了コード** で判定する。該当行は引数で渡す形に修正した。
2. `git commit` の検出正規表現が `git -c user.name=x commit` の形(オプションに値が付く)を見逃した。`git …(;&| 以外)… commit` に緩めた。

## 4. 観察

- **PostToolUse と PreToolUse の役割は違う。** 品質(lint / 型)は書いた後に直せばよいので PostToolUse で十分。秘密情報は書いた時点で害が出うるので PreToolUse でしか意味がない。
- **hook のテストは stdin JSON を手で作れば数秒で回る。** `tool_name` と `tool_input` の形さえ合わせれば Claude Code を起動する必要は無い。
- **fail-open を明示した。** `jq` が無い環境では黙って exit 0 する。CI 側の gitleaks があるから許容しているが、pre-commit を入れる Phase 2 で再検討する。
- 隣接セッションが `git add -A` で本 hook の初版(欠陥 1 を含む)を別コミットに巻き込んだ。**`git add -A` は「自分が意図した変更」以外も拾う**。
  今回は害が無かったが、これが `.env` だったら hook が止めるはずの事故そのものである。

## 5. 残作業

- Phase 2: lefthook の pre-commit と CI に gitleaks を追加し、hook の穴(引用符無し代入、Bash 経由の書き込み)を埋める
- Phase 0 残作業 6 のとおり、GitHub 側で secret scanning + push protection を有効化する
