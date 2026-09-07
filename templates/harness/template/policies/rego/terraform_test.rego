package terraform

import rego.v1

# 入力は conftest の hcl2 パーサと同じ形(ブロックは配列)にする
base := {"resource": {
	"aws_s3_bucket": {"cache": [{"bucket": "x"}]},
	"aws_s3_bucket_public_access_block": {"cache": [{"bucket": "${aws_s3_bucket.cache.id}", "block_public_acls": true, "block_public_policy": true, "ignore_public_acls": true, "restrict_public_buckets": true}]},
	"aws_security_group": {"alb": [{"ingress": [{"from_port": 443, "to_port": 443, "cidr_blocks": ["0.0.0.0/0"]}]}]},
}}

test_secure_baseline_passes if {
	count(deny) == 0 with input as base
}

test_open_ssh_denied if {
	bad := {"resource": {"aws_security_group": {"api": [{"ingress": [{"from_port": 22, "to_port": 22, "cidr_blocks": ["0.0.0.0/0"]}]}]}}}
	some msg in deny with input as bad
	contains(msg, "443 以外")
}

test_public_acl_denied if {
	bad := {"resource": {"aws_s3_bucket": {"pub": [{"bucket": "x", "acl": "public-read"}]}}}
	some msg in deny with input as bad
	contains(msg, "acl=")
}

test_missing_public_access_block_denied if {
	bad := {"resource": {"aws_s3_bucket": {"naked": [{"bucket": "x"}]}}}
	some msg in deny with input as bad
	contains(msg, "public_access_block")
}

test_iam_wildcard_denied if {
	bad := {"resource": {"aws_iam_policy": {"admin": [{"policy": "{\"Statement\":[{\"Effect\":\"Allow\",\"Action\":\"*\",\"Resource\":\"*\"}]}"}]}}}
	some msg in deny with input as bad
	contains(msg, "Action=*")
}
