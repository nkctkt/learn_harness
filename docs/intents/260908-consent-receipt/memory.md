# memory — この intent で起きたこと(/retro が読む)

各項目は `scripts/intent.sh note <見出し> "<本文>"` で追記する(ISO 時刻付き)。

## Interpretations
(曖昧だった指示をどう解釈したか)
- 2026-09-08T02:45:05Z — claude-code-guide の調査: AskUserQuestion の PostToolUse tool_response の形は公式ドキュメントに明記なし(tool_input / tool_response が渡ることのみ)。plan の「文字列リーフから Approve / Request Changes を探す」形非依存の取り出しを採用。u1 で実機確認用に HARNESS_DUMP_HOOK_INPUT=<path> があれば生入力を保存する仕掛けを hook に足す(通常は無効)
- 2026-09-08T02:55:42Z — plan-reviewer NOT-READY 3 件を反映: (1) AskUserQuestion は同一ターンで回答が返るので「ターンを終える」の意味を書き分け、規則は gate=<g> 付き HUMAN_TURN の最新だけを見る(Approve 後の発言で詰まない)。(2) 既存テストの human() の回帰を DoD に明記。(3) SINCE 定数は削除、Receipt の有無のみ。提案: ゲートの質問に [gate <g>] の印を付け、無関係な Approve を受領証にしない
- 2026-09-08T03:02:10Z — u1 実機確認: Claude Code の AskUserQuestion 応答から文字列リーフ探索で answer=Approve gate=plan が audit.log に記録された(2026-09-08T03:01:19Z)。tool_response の正確な形は未確認のまま(HARNESS_DUMP_HOOK_INPUT は settings に載せていない)

## Deviations
(計画や手順から意図的に外れた点と理由)

## Tradeoffs
(検討した代替と選ばなかった理由)

## Open questions
(次に人間に確認すべきこと)
