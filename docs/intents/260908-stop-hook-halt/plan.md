# plan — 260908-stop-hook-halt

## 設計判断

- ADR-0002(`docs/adr/0002-stop-hook-consultation-exception.md`): Stop hook は最も荷重の掛かる fail-safe で、例外を足すのは前例になる。戻すのは容易でも、次に緩めたい時はこの ADR を更新してからにする
- **skip 条件の判定は hook ではなく `scripts/intent.sh halt-reason` に置く。** hook は「`halt-reason` が理由を返したら skip して `STOP_SKIP <理由>` を記録、返さなければ従来どおり」だけ。
  理由: 時刻の比較(`iso_to_epoch`)は intent.sh に既にあり、hook に複製しない。判定の単体テストは `intent.test.sh`(一時ディレクトリ)で速く書ける。hook のテストは「skip する / しない」の 2 経路だけでよい。
- `halt-reason` の出力: `gate=intent` / `gate=plan`(state.md の `Gate <g>: presented` で、かつ audit.log の最新の `GATE_PRESENTED <g>` が 600 秒以内)、`open-questions`(最新の `NOTE	Open questions` が 600 秒以内)。両方あれば gate= を優先。
  **上限**: 600 秒以内の `STOP_SKIP` が既に 3 件あれば exit 1(note の連発で無期限に延長できない。plan-reviewer の指摘)。どの条件も無ければ exit 1、active intent が無ければ exit 1。intent.sh 自体が壊れていれば hook は skip しない(block 側に倒れる)。
- **skip は必ず記録する。** `intent.sh event STOP_SKIP <理由>`。allow を記録しない H1 の方針の例外で、理由は「Stop hook の回避経路は数えないと常態化に気づけない」(intent.md のリスク)。
- 窓の 600 秒と上限 3 回は定数(`HALT_WINDOW_SEC` / `HALT_MAX_SKIPS`)として intent.sh に置く。環境変数で変えられるようにはしない(スコープ外: 逃げ道は 2 つだけ)。テストは audit.log の時刻を書き換えて期限切れを作る。
- **DoD のテストは `verify.sh --changed` では走らない**(docs 段の `*.test.sh` は全体モードのみ)。各 unit の検証は `scripts/tests/hooks.test.sh` / `intent.test.sh` を直接叩くか `scripts/verify.sh --only docs`(全体)で行う。`--changed` が通っただけで done にしない。
- consent 方式ではゲートの回答は同一ターンに返るので「presented のまま Stop」は、Request Changes 後に直して再提示するまでの間に起きる。これも人間が輪の中にいる状態なので skip 対象(intent.md のリスク欄どおり)。

## 分解(Units)

```yaml
units:
  - name: u1-halt-reason-and-skip
    kind: service
    depends_on: []
  - name: u2-metrics-retro
    kind: library
    depends_on: [u1-halt-reason-and-skip]
  - name: u3-skills-docs
    kind: packaging
    depends_on: [u2-metrics-retro]
```

| Unit | 触るパス | 触れる境界 | 大きさ |
|---|---|---|---|
| u1-halt-reason-and-skip | `scripts/intent.sh`(`halt-reason`)、`.claude/hooks/stop-verify.sh`、`scripts/tests/intent.test.sh`、`scripts/tests/hooks.test.sh` | ハーネス(Stop hook。block 側に倒れること) | M |
| u2-metrics-retro | `scripts/intent.sh`(`metrics` に STOP_SKIP)、`.claude/skills/retro/SKILL.md`、`scripts/tests/{intent,harness-shape}.test.sh` | ハーネス(計測) | S |
| u3-skills-docs | `.claude/skills/{build-unit,plan-units}/SKILL.md`、`docs/lifecycle.md`、`scripts/tests/harness-shape.test.sh`、`templates/harness/template/**` | ハーネス(指示層、テンプレート) | S |

## 順序と walking skeleton

u1 が縦串: 「ゲート提示中 / Open questions → `halt-reason` → stop-verify が skip → `STOP_SKIP` が audit.log に出る」を、hooks.test.sh の既存の偽リポジトリ(失敗する verify.sh)で通す。
理由: 判定(intent.sh)と適用(hook)を同じ unit で閉じないと、片方だけ merge された状態が「skip されるべきなのに block」か「記録の無い skip」のどちらかになる。u2 / u3 はその後。

## Definition of Done

- u1:
  - `intent.test.sh`: 「halt-reason: gate presented(600 秒以内)で gate=<g>」「GATE_PRESENTED が 601 秒前なら exit 1」「Open questions の note 直後は open-questions」「note が 601 秒前なら exit 1」「ゲート未提示 + note 無しは exit 1」「intent 無しは exit 1」「presented と note が両方ある時は gate= を優先」「600 秒以内に STOP_SKIP が 3 件あれば条件を満たしても exit 1」「4 件目の STOP_SKIP が 601 秒前なら数えない」
  - `hooks.test.sh`(既存の FAKE リポジトリを流用): 「gate presented 中は verify 失敗でも exit 0 で `STOP_SKIP gate=plan` が記録される」「Open questions 直後は exit 0 で `STOP_SKIP open-questions`」「どちらも無ければ従来どおり exit 2 + `STOP_BLOCK`」「intent.sh が壊れている(exit 1)時は skip せず exit 2」「skip の時は verify.sh を実行しない(偽 verify.sh が呼ばれた痕跡が無い)」
  - 既存の assertion が全て通る
- u2:
  - `intent.test.sh`: 「metrics が STOP_SKIP を合計と理由別(`STOP_SKIP:gate` / `STOP_SKIP:open-questions`)に数える」
  - `harness-shape.test.sh`: 「retro skill の計測欄に `Stop skip` がある」
- u3:
  - `harness-shape.test.sh`: 「build-unit と plan-units の halt-and-ask 節に `STOP_SKIP` か `Stop hook` の語がある」「lifecycle.md に `STOP_SKIP` がある」
  - template drift 検査が通る(hook / intent.sh / tests / skill 3 本を同期)
  - `scripts/verify.sh --only docs` が全体で通る

## 検証計画

| AC | Unit | テスト / verify の段 |
|---|---|---|
| AC1 | u1 | `intent.test.sh`(halt-reason)、`hooks.test.sh`(skip + STOP_SKIP gate=) |
| AC2 | u1 | `intent.test.sh`(600 秒の窓)、`hooks.test.sh`(STOP_SKIP open-questions) |
| AC2b | u1 | `intent.test.sh`(上限 3 回) |
| AC3 | u1 | `hooks.test.sh`(従来の block、intent.sh 故障時、intent 無し) |
| AC4 | u2 | `intent.test.sh`(metrics)、`harness-shape.test.sh`(retro) |
| AC5 | u3 | `harness-shape.test.sh`(skill 2 本 + lifecycle の grep、drift) |

## ハーネスへの影響

- `stop-verify.sh`(Stop hook)の挙動が変わる: 2 条件で verify を skip。それ以外は不変。`guard-*` は触らない。CI は変更なし。
- 緩む方向の変更なので、skip の記録(`STOP_SKIP`)、窓(600 秒)、上限(3 回)、metrics の理由別可視化をセットにする。retro で回数が増えていたら ADR-0002 を更新して窓と上限を狭める。
- この intent が触るファイルはどの guard にも掛からない(plan-reviewer の指摘)。だからこそ窓と上限を hook 側に持たせ、「提示したまま放置して skip し続ける」経路を閉じる。
- HITL-4(CODEOWNERS)。hook 編集後は `bash -n`(lefthook)。
