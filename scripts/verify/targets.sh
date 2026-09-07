#!/usr/bin/env bash
# verify.sh が対象にするパッケージ・モジュールの一覧。プロジェクト固有の値はここだけに置く
# (templates/harness ではこのファイルだけが生成され、他の verify スクリプトはそのままコピーされる)。
# 空にした言語の段は「対象なし」として skip される。
TS_PACKAGES=(apps/api apps/web)                       # tsc / vitest を持つ pnpm workspace パッケージ
TS_ARCH_DIRS=(apps/api/src apps/web/src)              # dependency-cruiser の対象
TS_CONTRACTS_FILTER="@shelf/api"                      # contracts:check を持つパッケージ(無ければ空)
PY_PROJECTS=(services/enricher)                       # uv プロジェクト
GO_MODULES=(services/shortener)                       # go module
DOCKERFILES=(apps/api/Dockerfile apps/web/Dockerfile services/enricher/Dockerfile services/shortener/Dockerfile)
TERRAFORM_DIR=infra/terraform                         # 無ければ空
