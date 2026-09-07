#!/usr/bin/env bash
# Go: gofmt/goimports(整形)、go vet(コンパイラ隣接のバグ)、golangci-lint(staticcheck / gosec / errcheck 等)、
#     go test -race(データ競合検出はテストの実行時にしか出来ない)、govulncheck(到達可能な既知脆弱性のみ報告)。
# 責務の違い: vet は「ほぼ確実にバグ」、staticcheck は「たぶんバグ・非推奨」、gosec は「危険な API」、
#             -race は「並行実行して初めて分かる競合」、govulncheck は「実際に呼んでいる脆弱関数」。
set -uo pipefail
source "$(dirname "$0")/_lib.sh"
cd "$VERIFY_ROOT"
echo "[go]"
MODULES=(services/shortener)
command -v go >/dev/null 2>&1 || { echo "  - go not installed (CI で実行される)"; exit 0; }
export PATH="$PATH:$(go env GOPATH)/bin"

if [ $# -gt 0 ]; then
  files=(); while IFS= read -r _l; do files+=("$_l"); done < <(filter_files '\.go$|go\.(mod|sum)$' "$@")
  [ ${#files[@]} -eq 0 ] && { echo "  - no go files"; exit 0; }
fi

for mod in "${MODULES[@]}"; do
  if [ $# -gt 0 ]; then
    hit=0; for f in "${files[@]}"; do [[ "$f" == "$mod"/* ]] && hit=1; done
    [ $hit -eq 1 ] || continue
  fi
  pushd "$mod" >/dev/null
  if [ "$VERIFY_FIX" = 1 ]; then
    step "gofmt -w ($mod)" gofmt -w .
  else
    unformatted="$(gofmt -l .)"
    if [ -n "$unformatted" ]; then echo "  ✘ gofmt ($mod)"; printf '      %s\n' $unformatted; STEP_FAILED=1; else echo "  ✔ gofmt ($mod)"; fi
  fi
  step "go vet ($mod)" go vet ./...
  if command -v golangci-lint >/dev/null 2>&1; then
    if [ "$VERIFY_FIX" = 1 ]; then step "golangci-lint --fix ($mod)" golangci-lint run --fix ./...
    else step "golangci-lint ($mod)" golangci-lint run ./...; fi
  else echo "  - golangci-lint not installed (brew install golangci-lint)"; fi
  # --files(単一ファイル編集)ではテストを走らせない。--changed / 全体では -race 付きで実行。
  if [ "${VERIFY_MODE}" != files ]; then step "go test -race -cover ($mod)" go test -race -cover ./...; fi
  if [ "${VERIFY_MODE}" = all ]; then
    if command -v govulncheck >/dev/null 2>&1; then step "govulncheck ($mod)" govulncheck ./...
    else echo "  - govulncheck not installed (go install golang.org/x/vuln/cmd/govulncheck@latest)"; fi
  fi
  popd >/dev/null
done
exit $STEP_FAILED
