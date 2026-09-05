# Exercise 03 — テストと完了条件: 「テストした」を「テストが通った」に置き換える

- Phase: 2
- 日付: 2026-09-05
- PR: phase2/tests-and-completion

## 1. 導入したもの

| 層 | 追加 | 何を保証するか | 保証しないもの |
|---|---|---|---|
| コード | `apps/api/src/links/url.ts`(URL 正規化・公開ホスト判定)、`services/enricher/enricher/og.py`(OG パーサ)と振る舞いテスト | 以降の Phase の SSRF / 結合テストの土台 | - |
| verify.sh | 全体モードで `vitest --coverage` / `pytest --cov`、`--changed` で変更パッケージのテスト | テストが自動で走ること | テストの質 |
| Stop hook | `verify.sh --changed` が失敗したら完了を block(exit 2) | Agent が「完了」と言う前に、変更全体が format / lint / 型 / テストを通っていること | commit 済みの変更、`--no-verify` 経由の commit |
| lefthook pre-commit | staged ファイルの verify + gitleaks(未導入なら skip を明示)。commit-msg で Conventional Commits | 人間が `git commit` を打つ経路 | `--no-verify`。gitleaks 未導入端末 |
| CI | coverage を job summary に報告(ゲートにしない)、gitleaks を全履歴に対して実行 | 回避されていないこと | - |

## 2. Stop hook が必要だった実例(演習前に自分で踏んだ)

最初の commit は `pnpm test` だけを通して作った。Stop hook 相当の全体 verify を回すと 3 件落ちた。

| 欠陥 | 検出層 | なぜ `pnpm test` では通ったか |
|---|---|---|
| `import { ... } from "./url"` に `.js` が無い(NodeNext では TS2835) | tsc | Vitest は独自の解決を使うので拡張子無しでも動く |
| `url.ts` の整形漏れ | Biome | heredoc で書いたので PostToolUse hook が発火しなかった(Exercise 01 と同じ穴) |
| typescript-eslint の `no-unsafe-call` 多数 | eslint | 上の import が解決できず型が `error` 型になった連鎖 |

「テストが通る」と「verify が通る」は違う。Agent が自分の判断で「テストしたから完了」とすると、この 3 件はそのまま PR に乗る。Stop hook は判断を機械に移す層。

## 3. Stop hook の動作確認

```
# 変更が無い状態
echo '{}' | .claude/hooks/stop-verify.sh → exit 0(何もしない)

# heredoc で失敗するテストを書いた状態(PostToolUse hook は素通り)
echo '{}' | .claude/hooks/stop-verify.sh
→ 完了前チェック(scripts/verify.sh --changed)が失敗しました。...
  ✘ vitest (apps/api)
      AssertionError: expected 'https://a.com/' to be 'https://a.com/#x'
→ exit 2(block)
```

`stop_hook_active: true` の再入では何もしないので無限ループにはならない。

## 4. 同語反復テスト: カバレッジが測っていないもの

実装の出力をそのまま期待値にした「テスト」を書いた。

```ts
expect(normalizeUrl(input)).toEqual(normalizeUrl(input));
expect(out.host).toBe(out.host);
```

| 状態 | 同語反復テスト | 振る舞いテスト(`url.test.ts`) | `normalizeUrl` の行カバレッジ |
|---|---|---|---|
| 正常な実装 | 2 passed | 25 passed | 100%(同語反復だけで) |
| fragment 除去と host 小文字化をコメントアウト | **2 passed** | 1 failed(`lowercases the host and drops the fragment`) | 変わらず |

観察:

- **カバレッジは「実行された行」を数えるだけで、「検証された振る舞い」を数えない。** 同語反復テストだけで関数全行を通せる。
- AI Agent に「カバレッジ 80% 以上」を課すと、最短経路はこの種のテストになる。だから plan ではカバレッジを **報告のみ** にし、閾値を merge block にしない。
- 同語反復を機械的に検出するのが mutation testing(実装を壊してテストが落ちるか見る。今回手でやったことの自動化)。Phase 7 で Stryker / mutmut を週次に入れる。
- それまでの防衛線は「テストは振る舞いを検証し、実装の写しにしない」という AGENTS.md の規約と、Phase 7 の test-reviewer subagent。規約は request に過ぎないことを忘れない。

## 5. 秘密情報のコミット試行: どの層が止めたか

AWS 公式ドキュメントのサンプル鍵(無効)を `allow-secret` 無しで書き、`git add` して `git commit` を実行した。

```
PreToolUse:Bash hook error: guard-secrets: 拒否しました。
コミットしようとしている差分に秘密情報・個人情報らしき行があります(git diff の追加行を検査)。
staged:2: export const AWS_ACCESS_KEY_ID = "AKIA..."
staged:3: export const AWS_SECRET_ACCESS_KEY = "wJal..."
```

| 層 | 結果 | 備考 |
|---|---|---|
| PostToolUse hook | 素通り | heredoc で書いたため発火せず |
| **PreToolUse `guard-secrets.sh`**(PR #2) | **block** | `git commit` を含む Bash を、staged 差分を見て拒否。Bash 自体が実行されない |
| lefthook pre-commit(gitleaks) | 到達せず | 到達しても gitleaks 未導入のため skip。人間の commit ではここが最初の防衛線になるので、**ローカルに gitleaks を入れる意味はある** |
| CI gitleaks(全履歴) | 到達せず | commit できていれば PR で検出 |
| GitHub push protection | 到達せず | AWS の鍵はプロバイダパターンなので push 時にも止まるはず(未検証) |

同じ「秘密情報」を 5 層が見ているが、範囲(書込内容 / staged / 履歴全体)と主体(Agent のツール / 人間の git / サーバ)が全部違う。どれか 1 つで十分ということはない。

## 6. 途中で得た学び

- **Vitest と tsc は module 解決が違う。** NodeNext を使うなら `.js` 拡張子付き import が必須で、これは Vitest では気づけない。型検査をテストと別に走らせる理由がもう 1 つ増えた。
- **typescript-eslint は tsconfig に含まれないファイルを解析できない。** `vitest.config.ts` を ignore に入れた。設定ファイルはアプリロジックではないので許容。
- **lefthook の postinstall も pnpm 11 の `allowBuilds` で止まる。** root の `prepare` スクリプトで `lefthook install` を明示的に呼ぶ方が「何が git hooks を書き換えるか」が見えてよい。
- **`verify.sh --files` は pre-commit でも使える。** hook と pre-commit と CI が本当に同じスクリプトになった。

## 7. Phase 2 で防げるようになった欠陥

| 欠陥 | Phase 1 | Phase 2 |
|---|---|---|
| 失敗するテストを残したまま完了 | CI で検出 | Stop hook が完了を block、CI が二重に止める |
| テストを書かずに完了 | 検出手段なし | **まだ検出手段なし**(coverage は報告のみ)。Phase 7 の差分 coverage コメントと test-reviewer で可視化 |
| 同語反復テスト | 検出手段なし | 検出手段なし。Phase 7 の mutation testing まで持ち越し |
| ダミー鍵の commit | PreToolUse guard(PR #2) | + pre-commit gitleaks(導入端末)+ CI gitleaks(全履歴) |
| Conventional Commits 違反 | 規約のみ | commit-msg hook で拒否 |

## 8. 残課題

- `brew install gitleaks` をあなたの端末で実行すると pre-commit 層が有効になる(CI では既に動いている)。
- GitHub push protection の実動作は未検証。検証するなら `git commit --no-verify` で鍵入り commit を作って push し、拒否を確認してから `git reset` する(履歴に残さないよう注意)。
