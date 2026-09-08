# memory — この intent で起きたこと(/retro が読む)

各項目は `scripts/intent.sh note <見出し> "<本文>"` で追記する(ISO 時刻付き)。

## Interpretations
(曖昧だった指示をどう解釈したか)
- 2026-09-08T01:39:27Z — plan-reviewer NOT-READY 4 件を反映: スコープ外の自己矛盾(guard-bash §6 への追加を明示的な例外に)、u1 DoD の手動確認をテストに置換、記録はヘルパー内で判定直前に 1 回、経過時間は GNU/BSD 両対応の iso_to_epoch。提案 2 件(metrics.log の読み手と非対称の理由)も plan に明記
- 2026-09-08T02:19:00Z — test-reviewer(mutation で実測)の重大 2 件をテストに変換: detail のサニタイズ(タブ/改行/120 字)、HUMAN_TURN の厳密一致。中 1 件(intent.sh 自体が壊れている時の fail-safe)も stop-verify / post-edit-check / guard-edit で追加

## Deviations
(計画や手順から意図的に外れた点と理由)

## Tradeoffs
(検討した代替と選ばなかった理由)
- 2026-09-08T02:03:11Z — Edit の失敗回数(old_string 不一致)は PostToolUse に届かないため未計測のまま。Claude Code に PostToolUseFailure 相当の hook が無い限り hook からは観測できない。Exercise 13 では人間が手で数える

## Open questions
(次に人間に確認すべきこと)
- 2026-09-08T02:19:00Z — subagent(test-reviewer)の Bash 呼び出しも本体の hook を通り、active intent の audit.log に HOOK_ASK として記録された(このセッションで 9 件のうち数件)。計測の分母に subagent を含めるかは未決。区別するなら hook 入力の agent 情報が要る
