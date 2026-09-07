---
name: fix-ci
description: PR の CI が失敗した時に、GitHub の実行ログを読んで根本原因を直す手順。ローカルで再現 → 修正 → verify → push まで。テストの skip や閾値の緩和で通すことは禁止。
argument-hint: "[<pr-number>]"
---

# CI 失敗を Agent が読んで直す

ハーネスは「CI が失敗をログに残す」だけでは閉じない。**失敗を読んで直す経路**があって初めてループになる。

## 手順

1. **どの check が落ちたか**
   ```
   gh pr checks <pr>            # fail の行を見る
   gh run view <run-id> --json jobs --jq '.jobs[] | select(.conclusion=="failure") | {name, steps: [.steps[] | select(.conclusion=="failure") | .name]}'
   ```
2. **失敗ステップのログだけを読む**(全ログは長い。harden-runner の post step がノイズになる)
   ```
   gh run view --job <job-id> --log 2>/dev/null > /tmp/job.log
   grep -nE '✘|##\[error\]|FAIL|Error' /tmp/job.log | head
   ```
   `scripts/verify.sh` 由来なら `✘ <step名>` の直後 60 行に原因がある。
3. **ローカルで同じ段を再現する**(同じスクリプトなので原則同じ結果になる)
   ```
   scripts/verify.sh --only <ts|py|go|sec|infra>
   ```
   再現しない場合はツールのバージョン差を疑う(CI と local を揃える。Exercise 05 / 06 の trivy・shellcheck)。
4. **根本原因を直す。** 次は禁止:
   - テストの skip / `only` / 削除、期待値を実測値に書き換える
   - lint / 型の抑制コメントを理由無しに足す、閾値を下げる、`--ignore-unfixed` 等でスキャン範囲を狭める
   - CI の step を消す、`continue-on-error` を足す
   本当に誤検知なら、理由を書いて抑制し、PR 本文にその判断を残す。
5. **`scripts/verify.sh` を全体モードで通してから push**(Stop hook は `--changed` なので、sec / infra 段は自分で回す)。
6. PR 本文に「何が落ちて、なぜ、どう直したか」を追記する。同じ失敗が 2 回起きたら、ハーネス側(hook / verify.sh / docs)を直す。

## よくある原因(このリポジトリの実績)

| 症状 | 原因 | 参照 |
|---|---|---|
| ローカルは通るのに CI の biome / eslint が落ちる | heredoc で書いたファイルが hook を素通り。`.js` 拡張子無し import | Exercise 01 / 03 |
| trivy が CI だけ落ちる | trivy-action の SARIF モードは全 severity で exit-code を効かせる。バージョン差 | Exercise 05 |
| trivy image だけ落ちる | ベース image 由来の CVE(lockfile には無い) | Exercise 06 |
| actionlint が CI だけ落ちる | CI の shellcheck が新しい(`A && B \|\| C`) | Exercise 06 |
| 全 check 緑なのに merge できない | 未解決のレビュースレッド(code scanning のコメント) | Exercise 07 |
