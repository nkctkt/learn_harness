# docs/intents — 変更 1 件ごとの記録と承認ゲート

AI-DLC の「intent ごとの record dir + 追記専用の監査ログ」を、bash + markdown で最小に再実装したもの(Phase 9、`docs/plan.md` §12)。
1 つの intent = 1 つの目的を持つ変更(機能、バグ修正、リファクタ、ハーネス変更)。同時に active にできるのは 1 つ。

```
docs/intents/<YYMMDD>-<slug>/
├── intent.md    目的 / スコープ外 / 受け入れ条件 / リスクと HITL レベル      ← /intent が書き、人間が gate intent で承認
├── plan.md      分解(Units の DAG)/ 順序と walking skeleton / DoD          ← /plan-units が書き、plan-reviewer が読み、人間が gate plan で承認
├── state.md     Status / Scope / Stage / Gate ×2 / Units チェックボックス      ← scripts/intent.sh だけが書く
├── audit.log    追記専用 TSV(時刻 / イベント / 詳細)                           ← scripts/intent.sh と hook だけが書く
├── memory.md    Interpretations / Deviations / Tradeoffs / Open questions     ← intent.sh note で追記、/retro が読む
└── retro.md     学びと、ハーネスのどこに書き戻したか                            ← /retro が書く。無いと close できない
```

## 流れ(stage)

```
ideation ──gate intent──▶ inception ──gate plan──▶ construction ──全 unit done──▶ handoff ──merge──▶ operation ──/retro──▶ close
 /intent                   /plan-units + plan-reviewer          /build-unit ×N                /create-pr        /release /incident
```

- **ゲートは 2 択**(Approve / Request Changes)。提示したら **ターンを終える**。人間の応答が無い承認は `intent.sh` が拒否する。
- **人間の在席は hook が記録する**(`record-human-turn.sh`: UserPromptSubmit と AskUserQuestion の応答)。Agent は `gate approve` でそれを読むだけ。
- **計画承認前はアプリを触れない**(`guard-plan-approval.sh` が `apps/ services/ packages/ infra/ contracts/` への書込を deny)。
- `state.md` / `audit.log` を Edit / Write で直接書くと guard-edit が deny する。Bash のリダイレクトは guard-bash が ask にする。
- 記録は Git に入れて PR でレビューする。CI(`scripts/verify.sh --only docs`)が `intent.sh check` で整合性(提示 → 人間の応答 → 承認の順、state と audit の一致、必須節、unit DAG の循環)を検査する。

## 検出できないもの

- ローカルで audit.log を書き換えて HUMAN_TURN を捏造すること(全ローカル層と同じで、バイパス可能)。PR のレビューで `docs/intents/` の diff を見るのが最後の防衛線。
- 承認した人間が中身を読んだかどうか。
- intent.md / plan.md の内容の妥当性(それは plan-reviewer と人間の仕事)。

## 小さな変更

typo 修正や依存更新など、intent を作るほどでもない変更は作らなくてよい(hook は intent が無ければ何もしない)。
ただし `apps/` `services/` `infra/` の振る舞いを変える変更は intent を作る。判断に迷ったら作る(30 秒で済む)。
