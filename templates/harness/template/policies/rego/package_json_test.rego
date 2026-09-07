package package_json

import rego.v1

test_exact_allowed if {
	count(deny) == 0 with input as {"dependencies": {"hono": "4.13.5"}, "devDependencies": {"@shelf/x": "workspace:*"}}
}

test_caret_denied if {
	some msg in deny with input as {"dependencies": {"hono": "^4.13.5"}}
	contains(msg, "完全固定")
}

test_git_url_denied if {
	some msg in deny with input as {"dependencies": {"left": "github:user/left"}}
	contains(msg, "完全固定")
}

test_latest_denied if {
	some msg in deny with input as {"devDependencies": {"vitest": "latest"}}
	contains(msg, "完全固定")
}

test_postinstall_denied if {
	some msg in deny with input as {"scripts": {"postinstall": "node evil.js"}}
	contains(msg, "postinstall")
}
