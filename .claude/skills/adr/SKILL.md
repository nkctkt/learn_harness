---
name: adr
description: 元に戻しにくい設計判断(DB スキーマ、API 契約、依存・言語の追加、サービス境界、ハーネスの方針)を docs/adr/NNNN-<slug>.md に Architecture Decision Record として残す。Context / Decision / Consequences / Alternatives の 4 点。plan.md から参照する。
argument-hint: "<slug> \"<title>\""
---

# /adr — 「なぜこうなっているか」を判断した時点で残す

書くべき時: 実装後に戻しにくい、複数サービスに効く、議論があった、以前の判断を覆す。
書かない時: 変数名やフォーマット、すぐ戻せる選択、AGENTS.md / rules に既にある規約。

## 手順

1. 番号を決める: `ls docs/adr | sort | tail -n1`の次(4 桁ゼロ埋め)。
2. `docs/adr/NNNN-<slug>.md` を次の形で書く(各節 3〜8 行。長い ADR は読まれない):

   ```markdown
   # ADR-NNNN: <title>

   - Status: Proposed | Accepted | Deprecated | Superseded by ADR-XXXX
   - Date: YYYY-MM-DD
   - Intent: docs/intents/<id>(あれば)

   ## Context
   何が問題で、どの制約(性能 / 安全 / 保守 / 学習目的)が効いているか。既存のどの判断と関係するか。

   ## Decision
   能動態で 1〜2 文。「〜を採用する」「〜しない」。

   ## Consequences
   - 良くなること / 減るリスク
   - 悪くなること / 増えるリスク / できなくなること
   - 次に必要になる判断

   ## Alternatives
   - <代替 1>: 利点 / 却下理由
   - <代替 2>: ...
   ```
3. plan.md の「設計判断」から参照する。Status は承認ゲート(gate plan)の通過で `Accepted` にする。
4. 覆す時は新しい ADR を書き、古い方の Status を `Superseded by` にする。古い ADR は消さない。
