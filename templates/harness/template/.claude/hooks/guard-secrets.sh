#!/usr/bin/env bash
# PreToolUse(Edit|Write|MultiEdit|Bash): 秘密情報・個人情報がリポジトリに入る前に止める。
#
#   Edit/Write/MultiEdit … 書き込もうとしている内容とファイル名を検査し、該当すれば書き込み自体を拒否する。
#   Bash                 … `git commit` を含むコマンドのとき、staged 差分(-a なら未 staged も)を検査して拒否する。
#
# 検出できるもの: 既知フォーマットの鍵(AWS / GitHub / Anthropic / OpenAI / Slack / Google / 秘密鍵 / JWT)、
#                 `password = "..."` のような代入、資格情報入り DB URL、メールアドレス、携帯電話番号、
#                 `.env` `*.pem` `id_rsa` 等の「置いてはいけないファイル」への書き込み。
# 検出できないもの: 未知フォーマットの鍵、変数に分割された鍵、base64 で包まれた鍵、住所や氏名。
#                 → pre-commit / CI の gitleaks、GitHub push protection と重ねる(Phase 2)。
# 誤検知の逃がし方: その行に `allow-secret` を含める(例: `// allow-secret: AWS 公式ドキュメントのサンプル鍵`)。
#                 抑制した理由を同じ行に書くこと。ファイル単位・パターン単位の抑制は用意しない。
#
# exit 2 = block(stderr が Agent に渡る)。それ以外は許可。jq が無い環境では何もしない(fail-open を明示)。
set -uo pipefail
command -v jq >/dev/null 2>&1 || exit 0
input="$(cat)"
tool="$(printf '%s' "$input" | jq -r '.tool_name // empty')"
root="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# ---- 1. 内容パターン(ERE)。1 行ずつ照合する。 ----
# "-i" 付きは大文字小文字を無視する。
PATTERNS=(
  '(A3T[A-Z0-9]|AKIA|ASIA|ABIA|ACCA)[A-Z0-9]{16}'                                  # AWS access key id
  '-i:aws.{0,25}(secret|key).{0,25}["'"'"'][0-9A-Za-z/+]{40}["'"'"']'              # AWS secret access key
  '(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{36,}'                                          # GitHub token
  'github_pat_[A-Za-z0-9_]{22,}'                                                     # GitHub fine-grained PAT
  'sk-ant-[A-Za-z0-9_-]{20,}'                                                        # Anthropic API key
  'sk-(proj-)?[A-Za-z0-9_-]{32,}'                                                    # OpenAI API key
  'xox[baprs]-[0-9A-Za-z-]{10,}'                                                     # Slack token
  'AIza[0-9A-Za-z_-]{35}'                                                            # Google API key
  '-----BEGIN [A-Z ]*PRIVATE KEY-----'                                               # 秘密鍵
  'eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}'                # JWT
  '-i:(api[_-]?key|secret|token|passw(or)?d)["'"'"']?[[:space:]]*[:=][[:space:]]*["'"'"'][^"'"'"'[:space:]]{8,}["'"'"']'  # 汎用代入
  '-i:(postgres(ql)?|mysql|mongodb(\+srv)?|redis|amqp)://[^:/@[:space:]]+:[^@/[:space:]]{4,}@'   # 資格情報入り URL
  '[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}'                  # メールアドレス(個人情報)
  '0[789]0-[0-9]{4}-[0-9]{4}'                                                        # 携帯電話番号(個人情報)
)
# 明らかなプレースホルダ・公開値は汎用パターンから除外する(既知フォーマットの鍵には適用しない)。
PLACEHOLDER='-i:(example\.(com|org|net)|localhost|noreply|no-reply|xxx|changeme|change_me|placeholder|dummy|your[_-]|<[a-z_]+>|\$\{|%s|\{\{)'

scan_text() { # $1 = ラベル, stdin = テキスト。該当行を "ラベル:行番号: 内容" で stdout に出す。戻り値 1 = 該当あり
  local label="$1" hit=0 n=0 line
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    case "$line" in *allow-secret*) continue ;; esac
    local i
    for i in "${!PATTERNS[@]}"; do
      local p="${PATTERNS[$i]}" flag=""
      case "$p" in -i:*) flag="-i"; p="${p#-i:}" ;; esac
      if printf '%s\n' "$line" | grep -Eq $flag -- "$p"; then
        # 後半 4 つ(汎用代入 / URL / メール / 電話)だけプレースホルダ除外を適用する
        if [ "$i" -ge 10 ] && printf '%s\n' "$line" | grep -Eqi -- "${PLACEHOLDER#-i:}"; then continue; fi
        hit=1; printf '%s:%d: %s\n' "$label" "$n" "${line:0:160}"; break
      fi
    done
  done
  return $hit
}

# ---- 2. ファイル名パターン。 ----
forbidden_path() { # $1 = パス。置いてはいけないファイルなら 0
  local b; b="$(basename -- "$1")"
  case "$b" in
    .env|.env.*) [ "$b" = ".env.example" ] && return 1; return 0 ;;
    *.pem|*.key|*.p12|*.pfx|*.jks|*.keystore|id_rsa*|id_ed25519*|id_ecdsa*|*.tfstate|*.tfstate.*|credentials|credentials.json|service-account*.json|.npmrc|.pypirc|.netrc) return 0 ;;
  esac
  return 1
}

block() { # $1 = 理由, $2 = 該当行(複数行)。パイプで呼ぶと exit がサブシェルに閉じるので引数で渡す
  # 判定を記録する(Phase 10、improvement-plan H1)。exit 2 の直前に 1 回だけ。失敗しても判定は変えない。該当行(秘密)は記録しない。
  "$root/scripts/intent.sh" event HOOK_DENY "guard-secrets: ${1:0:80}" >/dev/null 2>&1 || true
  {
    echo "guard-secrets: 拒否しました。$1"
    [ -n "${2:-}" ] && printf '%s\n' "$2"
    echo
    echo "対処: 値はコードに書かず環境変数(process.env / os.environ)から読む。設定例は .env.example にプレースホルダで書く。"
    echo "      誤検知なら、その行に 'allow-secret: <理由>' を付ける。ファイル名が原因なら .gitignore 済みか確認し、別の置き場所を使う。"
  } >&2
  exit 2
}

case "$tool" in
  Edit|Write|MultiEdit)
    path="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')"
    [ -n "$path" ] && forbidden_path "$path" && block "秘密情報を置くためのファイル名です: $path"
    text="$(printf '%s' "$input" | jq -r '
      .tool_input as $t |
      ($t.content // empty),
      ($t.new_string // empty),
      (($t.edits // [])[] | .new_string // empty)')"
    [ -z "$text" ] && exit 0
    if out="$(printf '%s\n' "$text" | scan_text "${path:-<input>}")"; then exit 0; fi
    block "書き込もうとした内容に秘密情報・個人情報らしき行があります。" "$out"
    ;;
  Bash)
    cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')"
    printf '%s' "$cmd" | grep -Eq '(^|[^[:alnum:]_-])git[[:space:]]+([^;&|]*[[:space:]])?commit([[:space:]]|$)' || exit 0
    cd "$root" || exit 0
    git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
    # staged のファイル名を検査
    bad=""
    while IFS= read -r f; do [ -n "$f" ] && forbidden_path "$f" && bad="$bad$f"$'\n'; done < <(git diff --cached --name-only --diff-filter=ACMR)
    [ -n "$bad" ] && block "秘密情報を置くためのファイルが staged されています。git rm --cached で外してください。" "${bad%$'\n'}"
    # 追加行だけを検査(削除行は対象外)。-a / --all のときは未 staged の変更も含める。
    diff_args=(--cached)
    printf '%s' "$cmd" | grep -Eq -- '(^|[[:space:]])(-a|--all|-am|-a[[:alpha:]]+|-[[:alpha:]]*a[[:alpha:]]*)([[:space:]]|$)' && diff_args=(HEAD)
    added="$(git diff "${diff_args[@]}" --unified=0 --no-color --diff-filter=ACMR | grep -E '^\+[^+]' | sed 's/^+//')"
    [ -z "$added" ] && exit 0
    if out="$(printf '%s\n' "$added" | scan_text "staged")"; then exit 0; fi
    block "コミットしようとしている差分に秘密情報・個人情報らしき行があります(git diff の追加行を検査)。" "$out"
    ;;
esac
exit 0
