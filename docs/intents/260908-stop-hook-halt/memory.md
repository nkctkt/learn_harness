# memory — この intent で起きたこと(/retro が読む)

各項目は `scripts/intent.sh note <見出し> "<本文>"` で追記する(ISO 時刻付き)。

## Interpretations
(曖昧だった指示をどう解釈したか)
- 2026-09-08T04:36:48Z — plan-reviewer NOT-READY 2 件を反映: gate 提示中の skip にも 600 秒の窓、STOP_SKIP は窓内 3 回まで、metrics は理由別。提案 2 件も採用: DoD テストは --changed では走らない旨を plan に明記、ADR-0002 を追加
- 2026-09-08T05:37:25Z — test-reviewer(15 分予算・mutation 6 件の指示、実測 19 分): 7 mutation 中 6 件捕捉、1 件(halt-reason の exit code だけ壊す)は単体テストが素通り → 4 assertion に rc 検査を追加。metrics の 3 条件 && を 3 assertion に分割

## Deviations
(計画や手順から意図的に外れた点と理由)

## Tradeoffs
(検討した代替と選ばなかった理由)

## Open questions
(次に人間に確認すべきこと)
