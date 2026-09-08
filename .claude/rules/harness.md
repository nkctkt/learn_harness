---
paths:
  - ".claude/**"
  - "scripts/**"
  - "policies/**"
  - ".github/**"
  - "lefthook.yml"
  - "templates/**"
---

# ハーネス自体(hooks / skills / verify / policies / CI / templates)

- hook は bash 3.2(macOS)で動く。編集後は必ず `bash -n`。構文エラーは exit 2 = 全ツール block(Exercise 04)。
- PreToolUse hook は `trap on_err ERR` で fail-closed(deny)。判断はしない。パターン一致で止めるだけ。数秒で返す。
- hook のテストは対話ではなくファイルに書く(`scripts/tests/*.test.sh`)。guard-bash が Bash 文字列全体を見るため。記録は `INTENTS_DIR` を一時ディレクトリにして触る。
- 変数の直後に日本語を書かない(`$a。` は bash 3.2 で `a。` という変数名になる)。`${a}。` と書く。
- `verify.sh` は「同じスクリプト、違う範囲」。段を足す時は `--files` / `--changed` / 全体の 3 モードを実装し、未導入ツールは skip を明示して exit 0。
- workflow / settings.json / policies の変更は PR に理由を書く(AGENTS.md)。action は SHA 固定(Rego が落とす)。
- リポジトリ側を変えたら `templates/harness/template/` を同期する(同一ファイルはコピー、固有値は Jinja)。
- guard-bash はパスの **位置** を見ない。`/tmp` に取ったリポジトリのコピーで `.claude/hooks/` を `sed -i` しても ask になり、active intent の audit.log に記録される(subagent の mutation テストで 22 件)。コピーで作業する時は hook を通らない方法(Read / Write ツール、`intent.sh` を無効化した環境)を使うか、記録に混ざることを前提に読む。
- テンプレートへの `cp` も guard-bash §8 の ask になる(パスに `.claude/hooks/` を含むため)。同期は 1 コマンドにまとめる(improvement-plan M1 で自動化予定)。
