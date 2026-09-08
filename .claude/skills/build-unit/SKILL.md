---
name: build-unit
description: 承認済み plan.md の unit を 1 つ実装する。unit start → DoD のテストを先に用意 → 最小実装 → verify(--changed と、境界を触るなら結合)→ コミット → unit done。AI-DLC の Construction(code-generation / build-and-test)に相当。計画から外れたら勝手に直さず halt-and-ask。
argument-hint: "<unit-id>"
---

# /build-unit — 1 unit を、計画どおりに、検証付きで閉じる

前提: `scripts/intent.sh status` が `stage=construction`(= gate plan 承認済み)。unit が `[ ]`。
1 回の実行で 1 unit。次の unit は `depends_on` が全て `[x]` になってから。

## 手順

1. **開始を記録**: `scripts/intent.sh unit start <unit-id>`。plan.md のその unit の行(触るパス、境界、DoD)を読み直す。
2. **DoD をテストにする(実装より先)**
   - DoD に書いたテスト名を、失敗する状態で先に作る(既存テストの拡張でよい)。「実装をなぞるテスト」は書かない(`test-reviewer` が指摘する観点: 同語反復、assertion 不足、境界値、モックしすぎ)。
   - 契約(`contracts/`)を変えるなら api 側 `contracts.ts` → 再生成 → producer の契約テストの順。
3. **最小の実装**。触るパスは plan.md に書いた範囲。範囲外を触りたくなったら 6 へ。
   - 領域ルール(`.claude/rules/*.md`)が自動で読まれる。境界(zod / pydantic / fetch_html / SQL)は AGENTS.md の規約どおり。
4. **検証**
   ```
   scripts/verify.sh --changed                       # Stop hook と同じ
   INTEGRATION=1 pnpm --filter @shelf/api test:coverage   # DB 境界を触ったら
   scripts/verify.sh --only sec                      # 外部入力 / SQL / fetch を触ったら(Semgrep)
   ```
   落ちたら根本原因を直す。skip / 抑制 / 閾値緩和で通さない(`/fix-ci` の禁止事項と同じ)。
5. **記録とコミット**
   - 解釈・逸脱・トレードオフがあれば `scripts/intent.sh note <見出し> "..."`(後で /retro が読む)。
   - Conventional Commits、scope に unit 名: `feat(links): u2 — short code lookup`。1 unit = 1〜数コミット。
   - `scripts/intent.sh unit done <unit-id>`。
6. **walking skeleton(u1)は特別**: 全ての結合点を実際に通してから done にする(`docker compose up --build` で `web → api → enricher / shortener` を 1 回叩く)。ここで結合の問題が出るのが目的。

## halt-and-ask(計画から外れる時)

次のどれかが起きたら、直さずに止まる: DoD が満たせない / 触るパスが増える / 契約や境界の変更が必要 / 依存追加が必要。
`scripts/intent.sh note "Open questions" "<何が起きたか>"` → ターンを終えて人間に聞く(その場で決められる問いなら AskUserQuestion でもよい)。
落ちたテストを抱えたままでよい: note の直後 600 秒以内(3 回まで)は Stop hook が verify を skip し、`STOP_SKIP open-questions` を記録する(ADR-0002)。落ちたテストは CI が受ける。
skip は数えられている。相談以外の目的で note を書かない(retro で回数が見える)。
計画の実質が変わるなら `/plan-units` の「承認後に計画を変えたくなったら」に従う(承認を取り直す)。
依存追加は `/add-dependency`(HITL-4)。

## 全 unit が `[x]` になったら

`scripts/intent.sh stage handoff` → `/create-pr`。
