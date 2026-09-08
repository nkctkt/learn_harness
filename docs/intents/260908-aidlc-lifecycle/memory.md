# memory — この intent で起きたこと(/retro が読む)

各項目は `scripts/intent.sh note <見出し> "<本文>"` で追記する(ISO 時刻付き)。

## Interpretations
(曖昧だった指示をどう解釈したか)
- 2026-09-08T00:17:45Z — AI-DLC のエンジンは借りず、仕組み(record dir / HARD STOP / HUMAN_TURN / plan-approval guard / SessionStart 再注入 / memory 層 / Learnings Ritual)だけを bash で再実装した(ADR-0001)。

## Deviations
(計画や手順から意図的に外れた点と理由)
- 2026-09-08T00:17:45Z — この intent は事後に作った。計画承認前にコードを書くことを禁止する hook 自体を作る作業だったため、u1〜u4 は gate plan の承認より先に実装済み。次の intent からは順序どおり(ゲートが効く)。

## Tradeoffs
(検討した代替と選ばなかった理由)

## Open questions
(次に人間に確認すべきこと)
- 2026-09-08T00:17:45Z — intent を必須にするか(HARNESS_REQUIRE_INTENT=1)。まず任意で運用し、intent 無しで apps を触った回数を次の retro で数える。
