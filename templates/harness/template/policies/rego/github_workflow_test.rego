package github_workflow

import rego.v1

pinned := {"jobs": {"a": {"steps": [{"uses": "actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803 # v6"}]}}, "on": {"pull_request": null}, "permissions": {"contents": "read"}}

test_pinned_action_allowed if {
	count(deny) == 0 with input as pinned
}

test_tag_reference_denied if {
	bad := object.union(pinned, {"jobs": {"a": {"steps": [{"uses": "actions/checkout@v6"}]}}})
	some msg in deny with input as bad
	contains(msg, "commit SHA")
}

test_local_action_allowed if {
	ok := object.union(pinned, {"jobs": {"a": {"steps": [{"uses": "./.github/actions/setup"}]}}})
	count(deny) == 0 with input as ok
}

test_pull_request_target_denied if {
	bad := object.union(pinned, {"on": {"pull_request_target": null}})
	some msg in deny with input as bad
	contains(msg, "pull_request_target")
}

# YAML 1.1 パーサは `on:` を true キーにする。その形でも検出できること。
test_pull_request_target_denied_with_boolean_on_key if {
	bad := {"jobs": {}, "true": {"pull_request_target": {"types": ["opened"]}}, "permissions": {"contents": "read"}}
	some msg in deny with input as bad
	contains(msg, "pull_request_target")
}

test_pull_request_target_in_list_denied if {
	bad := object.union(pinned, {"on": ["push", "pull_request_target"]})
	some msg in deny with input as bad
	contains(msg, "pull_request_target")
}

test_missing_permissions_denied if {
	bad := object.remove(pinned, ["permissions"])
	some msg in deny with input as bad
	contains(msg, "permissions")
}

test_write_all_denied if {
	bad := object.union(pinned, {"permissions": "write-all"})
	some msg in deny with input as bad
	contains(msg, "write-all")
}

test_untrusted_interpolation_denied if {
	bad := object.union(pinned, {"jobs": {"a": {"steps": [{"run": "echo \"${{ github.event.pull_request.title }}\""}]}}})
	some msg in deny with input as bad
	contains(msg, "script injection")
}
