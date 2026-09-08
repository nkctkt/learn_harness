# plan — 260908-consent-receipt

## 設計判断

- ADR: なし(受領証の形式変更は `audit.log` の detail 列の追加であり、旧記録と互換。戻すのも 1 行)
- **回答の取り出しは形に依存させない。** `record-human-turn.sh` は `tool_response` の文字列リーフ全部(`[.. | strings]`)から `Approve` / `Request Changes` に完全一致するものを探し、見つかった時だけ `answer=<label>` を付ける。
  AskUserQuestion の応答 JSON の正確な形(キー名、配列か map か)は公式ドキュメントに明記が無い(claude-code-guide で確認、memory.md)。この方式なら形が判明していなくても動き、自由記述(Other)や他の質問の回答はラベルに一致しないので `answer=` が付かない(= 承認に使えない、fail-closed)。
  実機確認のため、`HARNESS_DUMP_HOOK_INPUT=<path>` が設定されている時だけ生入力をそのファイルに追記する(通常は未設定)。
- **ゲートの質問には印を付け、hook は印のある質問の回答だけを受領証にする。** skill はゲートの AskUserQuestion の質問文に `[gate intent]` / `[gate plan]` を含める。hook は `tool_input` の文字列リーフにその印があった時だけ `answer=<label> gate=<name>` を記録する。
  曖昧点確認の AskUserQuestion にたまたま "Approve" というラベルがあっても受領証にならず、intent ゲートの Approve を plan ゲートに流用することもできない。
- **承認の規則(consent)**: 提示(GATE_PRESENTED <g>)より後の HUMAN_TURN のうち **`gate=<g>` を持つものの最新** が `answer=Approve` なら承認できる。`gate=` を持たない HUMAN_TURN(UserPromptSubmit、曖昧点確認の回答)は無視する。
  これにより「Approve の後に人間が何か発言したら承認が恒久的に止まる」詰みが無い。Request Changes の後に Approve が来れば最新が Approve なので通る。
- **ターンの意味を書き分ける。** AskUserQuestion の回答は同じ推論ターン内に返る。skill / rules の「ゲートを提示したらターンを終える」は「AskUserQuestion を出して回答を待つ(= 人間の入力までは何もしない)」の意味になり、回答が Approve なら **同じターンの直後に** `gate approve` を呼ぶ(人間の追加入力を挟まない)。Request Changes なら `gate reject` して直す。
- **新旧の規則は state.md の `Receipt:` フィールドで切り替える。** `intent.sh new` は `- Receipt: consent` を書く。フィールドが無い intent は旧規則(提示後に HUMAN_TURN があればよい)。
- **時刻定数(SINCE)による新旧判定は置かない。** merge 時刻は commit 時点で分からず、外れると誤検知になる。`Receipt:` フィールドの有無だけで切り替え、フィールドを消す改竄は guard-edit / guard-bash の deny と PR での `docs/intents/` diff レビューに委ねる(既存の二重防御。三重目の弱い防御を足さない)。
- ADR は書かない理由: 承認ゲートの意味論(在席 → 同意)は変わるが、記録形式は互換で、戻すのは hook 1 行と規則 1 箇所。戻しにくさが無い。意味論の変更は `docs/lifecycle.md` §4 に書く。
- **この intent 自身は旧形式**(`Receipt:` 無しで作られた)。plan ゲートは旧規則で承認する。新規則が効くのは次の intent から。`docs/lifecycle.md` にそう書く。
- `gate reject` は変えない(Agent が人間の Request Changes を読んで実行する。誤って reject しても再提示で戻れる)。

## 分解(Units)

```yaml
units:
  - name: u1-answer-receipt
    kind: service
    depends_on: []
  - name: u2-consent-gate
    kind: library
    depends_on: [u1-answer-receipt]
  - name: u3-skills-rules-docs
    kind: packaging
    depends_on: [u2-consent-gate]
```

| Unit | 触るパス | 触れる境界 | 大きさ |
|---|---|---|---|
| u1-answer-receipt | `.claude/hooks/record-human-turn.sh`、`scripts/tests/hooks.test.sh` | ハーネス(hook。exit 0 のまま、記録の detail だけ変える) | S |
| u2-consent-gate | `scripts/intent.sh`(`new` / `gate approve` / `check`、定数)、`scripts/tests/intent.test.sh` | ハーネス(承認の規則) | M |
| u3-skills-rules-docs | `.claude/skills/{intent,plan-units}/SKILL.md`、`.claude/rules/intents.md`、`docs/lifecycle.md`、`scripts/tests/harness-shape.test.sh`、`templates/harness/template/**` | ハーネス(指示層、テンプレート) | S |

## 順序と walking skeleton

u1 が縦串: 「AskUserQuestion の応答 → hook → `HUMAN_TURN … answer=Approve`」の 1 行が audit.log に出るところまでを、承認の規則を変えずに通す。
理由: 受領証の **発行側**(hook)が先。規則(u2)を先に変えると、hook が answer を書けない環境では全ての承認が止まる。u1 を merge 前に実機で 1 回動かして(このセッションの plan ゲートを AskUserQuestion で出す)、形に依存しない取り出しが実際に `answer=Approve` を書くことを確認してから u2 に進む。

## Definition of Done

- u1: `hooks.test.sh` に次が通る
  - 「AskUserQuestion の応答に `Approve` があると `HUMAN_TURN	PostToolUse:AskUserQuestion answer=Approve` が記録される」(map 形と配列形の 2 fixture)
  - 「`Request Changes` は `answer=Request Changes`」
  - 「自由記述(どのラベルにも一致しない)は `answer=` 無し」
  - 「UserPromptSubmit は従来どおり `HUMAN_TURN	UserPromptSubmit`」
  - 「`[gate plan]` の印が無い質問の Approve は `answer=` を付けない」
  - 「`HARNESS_DUMP_HOOK_INPUT` 設定時は生入力がファイルに追記され、未設定なら何も書かない」
  - 実機: この intent の plan ゲートを `[gate plan]` 付き AskUserQuestion で出し、audit.log に `answer=Approve gate=plan` が実際に記録される(memory.md に記録。承認自体はこの intent が旧形式なので従来規則)
- u2: `intent.test.sh` に次が通る
  - 「new は state.md に `Receipt: consent` を書く」
  - 「consent: 提示後に UserPromptSubmit だけでは承認できない(理由に AskUserQuestion と [gate <g>])」
  - 「consent: `answer=Request Changes gate=intent` では承認できない」
  - 「consent: `answer=Approve` でも `gate=` が別のゲート(intent の Approve で plan を承認)なら拒否」
  - 「consent: `answer=Approve gate=<g>` があれば承認できる」
  - 「consent: Approve の **後に** UserPromptSubmit が来ても承認できる(gate= 無しは無視)」
  - 「consent: Approve の後に `answer=Request Changes gate=<g>` が来ると承認できない(最新の gate= 付きが優先)」
  - 「consent: 提示より前の Approve は使えない(再提示後に古い Approve で承認できない)」
  - 「legacy(state.md に Receipt 無し)は従来どおり UserPromptSubmit で承認できる」(テスト内で state.md から Receipt 行を消した intent を組み立てる)
  - 「check: consent の intent で GATE_APPROVED より前の最新の gate=<g> 付き HUMAN_TURN が answer=Approve でなければ落ちる」
  - 「check: 既存の `docs/intents/260908-*` 2 件(旧形式)は通る」(本物の記録に対して `intent.sh check`)
  - 既存テストの回帰: `intent.test.sh` の `human()` と `hooks.test.sh` の承認フローは `new` が consent を書くようになると失敗する。`human()` を「`answer=Approve gate=<g>` を書く版」(`human_approve <g>`)に置き換え、legacy 規則の確認だけ Receipt 無しの state.md で行う。両テストの assertion 数は減らさない
- u3:
  - `harness-shape.test.sh` に「`/intent` と `/plan-units` の SKILL.md に `AskUserQuestion` と `Approve` の語がある」が通る
  - template drift 検査が通る(hook / intent.sh / tests / skill 2 本 / rules を同期)
  - `scripts/verify.sh --only docs` が全体で通る

## 検証計画

| AC | Unit | テスト / verify の段 |
|---|---|---|
| AC1 | u1 | `hooks.test.sh`(docs 段)+ 実機 1 回 |
| AC2 | u2 | `intent.test.sh` |
| AC3 | u2 | `intent.test.sh`(new の出力、legacy の承認)、本物の 2 intent への `check` |
| AC4 | u2 | `intent.test.sh`(check の改竄検出 2 種) |
| AC5 | u3 | `harness-shape.test.sh` |
| AC6 | u3 | `harness-shape.test.sh`(drift)、lifecycle.md は目視ではなく drift 対象外なので記述の有無を `grep` で検査に含める |

## ハーネスへの影響

- hook 1 本(`record-human-turn.sh`、常に exit 0 のまま)、`scripts/intent.sh`、テスト 3 本、skill 2 本、rules 1 本、templates。HITL-4(CODEOWNERS)。
- `guard-*` の判定条件は変えない。CI は変更なし(docs 段が検査する)。
- 承認の規則が厳しくなる方向のみ。緩む経路は「state.md から Receipt を消す」だけで、guard-edit / guard-bash の deny と PR の diff レビューで塞ぐ(既存)。
- 人間側の変化: ゲートは `[gate <g>]` 付きの AskUserQuestion で出る。テキストで「approve」と打っても承認されない(hook が answer を書かないため)。`gate approve` の拒否理由がそれを案内する。
- Agent 側の変化: 回答が返った同じターンで `gate approve` / `gate reject` を呼ぶ。人間の追加入力を待たない。
