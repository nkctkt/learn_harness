---
paths:
  - "docs/intents/**"
  - "docs/adr/**"
---

# docs/intents(記録と承認ゲート)/ docs/adr

- `state.md` と `audit.log` は `scripts/intent.sh` だけが書く。Edit / Write は guard-edit が deny する。
- ゲートは質問文の先頭に `[gate intent]` / `[gate plan]` を書いた **AskUserQuestion** で出し、選択肢は Approve / Request Changes の 2 つだけ(3 択目を発明しない)。回答が返った **同じターン** で `gate approve` / `gate reject` を呼ぶ。テキストの返答は承認にならない(hook が `answer=` を書かない)。`Receipt: consent` の intent はこれが無いと `intent.sh` が承認を拒否する。
- ゲートで人間に見せるのは 3 つだけ: 作ったもの(パス付き)、見てほしい所、承認後に起きること。仕組みの説明で承認を正当化しない。
- 曖昧な点は AskUserQuestion で聞く(最大 3 問)。質問文に `[gate` を書かない。答えは HUMAN_TURN になるが、それは承認ではない(hook は印の無い質問の回答を受領証にしない)。
- memory.md には `intent.sh note` で「解釈 / 逸脱 / トレードオフ / 未確認」を随時残す。/retro がそれを読む。
- ADR は元に戻しにくい判断だけ(`/adr`)。ファイル命名 `docs/adr/NNNN-<slug>.md`、Status を持つ。
- `audit.log` の未コミット差分(HUMAN_TURN / HOOK_*)は hook が書いたもの。branch を切り替える前に commit に含める(`git checkout` が差分で止まる)。消さない。
