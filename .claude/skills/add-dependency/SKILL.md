---
name: add-dependency
description: 新しい依存(npm / PyPI)を追加する時の手順。実在確認・保守状況・ライセンス・脆弱性・公開日を確認してから追加し、理由をコミットに残す。
argument-hint: "<ecosystem> <package> [<reason>]"
---

# 依存の追加

AI が推奨するパッケージの約 2 割は存在しない(slopsquatting の温床)。存在しても放置されていたり、公開直後の悪性版だったりする。
追加は「入れてから考える」ではなく、次を順に確認してから行う。

## 手順

1. **実在と正体の確認**(名前の typo・似た名前の別物を排除)
   - npm: `pnpm view <pkg> name version time.modified repository.url license`
   - PyPI: `curl -s https://pypi.org/pypi/<pkg>/json | jq '{name, version: .info.version, home: .info.home_page, license: .info.license}'`
   - リポジトリ URL が本物のプロジェクトを指しているか、README の説明と一致するかを見る。
2. **保守状況**: 最終更新が 2 年以上前、メンテナ 1 人、issue 放置なら代替を探す。標準ライブラリで済むなら入れない。
3. **ライセンス**: MIT / Apache-2.0 / BSD / ISC / 0BSD / MPL-2.0 は可。GPL / AGPL / SSPL / 独自ライセンスは人間に確認(HITL-4)。
4. **既知脆弱性**: 追加後に `scripts/verify.sh --only sec`(Trivy が lockfile を見る)。HIGH 以上が出たら別の版か代替。
5. **公開日**: `minimumReleaseAge`(7 日)により pnpm は新しすぎる版を解決しない。急ぐ理由があっても回避しない。
6. **追加**: バージョンは完全固定(pnpm は `saveExact`、uv は lockfile)。`pnpm add` / `uv add` のみ。lockfile は手で触らない。
7. **コミット**: メッセージ本文に「何のために・なぜこれを選んだか・代替は何か」を書く。

## やらないこと

- グローバルインストール、uv 環境外の pip、リモートスクリプトをシェルにパイプする導入。
- 依存を増やすだけの「便利関数」パッケージ(左パッド系)。
- `--ignore-scripts` を外すこと。install スクリプトが必要な依存は `pnpm-workspace.yaml` の `allowBuilds` に理由付きで書く。
