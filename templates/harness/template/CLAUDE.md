@AGENTS.md

## Claude Code 固有の指示

- 各 Phase の作業は「概念説明 → 最小実装 → 実行 → 意図的に壊す → 検出確認 → 修正 → `docs/exercises/` に記録」の順で進める。
- 品質ツールを導入する時は、何を検出でき何を検出できないか、どの層(Hook / pre-commit / CI / Nightly)で動かすかを必ず説明する。
- `docs/plan.md` と実装が乖離したら、実装ではなく plan を先に更新する。
