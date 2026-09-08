---
paths:
  - "docs/intents/**"
  - "docs/adr/**"
---

# docs/intents(記録と承認ゲート)/ docs/adr

- `state.md` と `audit.log` は `scripts/intent.sh` だけが書く。Edit / Write は guard-edit が deny する。
- ゲートは 2 択(Approve / Request Changes)で提示し、**提示したらターンを終える**。人間の応答(hook が記録する HUMAN_TURN)が無い承認は `intent.sh` が拒否する。3 択目を発明しない。
- ゲートで人間に見せるのは 3 つだけ: 作ったもの(パス付き)、見てほしい所、承認後に起きること。仕組みの説明で承認を正当化しない。
- 曖昧な点は AskUserQuestion で聞く(最大 3 問)。答えは HUMAN_TURN になるが、それは承認ではない。
- memory.md には `intent.sh note` で「解釈 / 逸脱 / トレードオフ / 未確認」を随時残す。/retro がそれを読む。
- ADR は元に戻しにくい判断だけ(`/adr`)。ファイル命名 `docs/adr/NNNN-<slug>.md`、Status を持つ。
- `audit.log` の未コミット差分(HUMAN_TURN / HOOK_*)は hook が書いたもの。branch を切り替える前に commit に含める(`git checkout` が差分で止まる)。消さない。
