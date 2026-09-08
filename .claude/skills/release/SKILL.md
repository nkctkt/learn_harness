---
name: release
description: main の merge 済みコミットに semver タグを打って release.yml(GHCR push、SLSA provenance、CycloneDX SBOM、Trivy image gate)を走らせ、gh attestation verify で出荷物の出所を確認して記録する。AI-DLC の Operation(deployment-execution)に相当。タグは消さない、force しない。
argument-hint: "<vX.Y.Z>"
---

# /release — 「この image はこのコミットからこの workflow で作られた」を検証可能にする

前提: `main` が最新で、対象の PR が merge 済み。intent があれば `stage=operation`。
リリースは元に戻せない操作(タグとレジストリは公開される)。**バージョンは人間が決める**(HITL-3)。Agent は提案と検証を行う。

## 手順

1. **バージョンを提案する**: 前回タグ(`git describe --tags --abbrev=0`)からの Conventional Commits を読み、`feat` → minor、`fix` → patch、`!` / `BREAKING CHANGE` → major。人間の確定を待つ(AskUserQuestion)。
2. **タグを打つ**(`main` の HEAD、annotated)
   ```
   git checkout main && git pull --ff-only
   git tag -a vX.Y.Z -m "release vX.Y.Z: <1 行>"
   git push origin vX.Y.Z
   ```
3. **workflow を見届ける**: `gh run list --workflow release.yml --limit 1` → `gh run watch <id>`。Trivy image gate(HIGH 以上、修正版あり)で落ちたらタグを消さず、修正して **次のパッチ版** を出す。
4. **出所を検証する**(全 image)
   ```
   gh attestation verify oci://ghcr.io/<owner>/<repo>/<image>:vX.Y.Z --repo <owner>/<repo>
   gh attestation verify oci://ghcr.io/<owner>/<repo>/<image>:vX.Y.Z --repo <owner>/<repo> --predicate-type https://cyclonedx.org/bom
   ```
   両方 exit 0 で「provenance と SBOM がレジストリの外(GitHub の attestation store)から検証できる」状態。
5. **記録する**: intent があれば `scripts/intent.sh note Interpretations "release vX.Y.Z: <検証結果>"`。`docs/exercises/` の該当 Phase に検証コマンドと結果を追記。
6. **ロールバック方針**: 前のタグの image は GHCR に残る。戻すのは「前のタグをデプロイし直す」であって、タグの削除・上書きではない(Rulesets が tag の削除を禁止している)。

## やらないこと

- `git push --force`、タグの付け直し(同名タグは 2 度と使わない)。
- release job の権限(`packages` / `id-token` / `attestations`)を PR の workflow に広げる。
- Trivy image gate を `--ignore-unfixed` 以上に緩める。
