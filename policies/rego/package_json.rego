# package.json の依存宣言ポリシー。AGENTS.md の「バージョンは完全固定」を機械検査にする。
#   conftest test --policy policies/rego --namespace package_json package.json apps/*/package.json
package package_json

import rego.v1

dep_fields := ["dependencies", "devDependencies", "optionalDependencies"]

deny contains msg if {
	some field in dep_fields
	some name, spec in input[field]
	not startswith(spec, "workspace:")
	not regex.match(`^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?$`, spec)
	msg := sprintf("%s.%s = %q: バージョンは完全固定(x.y.z)にしてください(範囲・タグ・URL・git は不可)", [field, name, spec])
}

# install 時に任意コードが走る経路。root の scripts に preinstall/postinstall を置かない(lefthook は prepare で明示)。
deny contains msg if {
	some hook in ["preinstall", "postinstall", "preprepare", "postprepare"]
	input.scripts[hook]
	msg := sprintf("scripts.%s は禁止です(install 時の任意コード実行)。必要なら prepare に明示してください", [hook])
}
