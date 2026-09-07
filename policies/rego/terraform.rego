# Terraform(HCL)の組織ポリシー。Trivy config が汎用の misconfig を見るのに対し、ここは「うちでは絶対に無し」を書く。
#   conftest test --policy policies/rego --namespace terraform --parser hcl2 infra/terraform/*.tf
# 注意: hcl2 パーサは同名ブロックを配列にする。resource.aws_s3_bucket.cache は [ {...} ]。ingress も配列。
package terraform

import rego.v1

# 1) セキュリティグループの ingress を 0.0.0.0/0 に開けてよいのは 443 だけ(ALB 想定)。SSH/DB 等は不可。
deny contains msg if {
	some name, blocks in input.resource.aws_security_group
	some sg in blocks
	some rule in sg.ingress
	some cidr in rule.cidr_blocks
	cidr == "0.0.0.0/0"
	not rule.from_port == 443
	msg := sprintf("aws_security_group.%s: ingress %v-%v を 0.0.0.0/0 に公開しています。443 以外の公開は禁止です", [name, rule.from_port, rule.to_port])
}

# 2) S3 バケットの公開 ACL は禁止(bucket 属性でも別リソースでも)。
deny contains msg if {
	some name, blocks in input.resource.aws_s3_bucket
	some b in blocks
	b.acl in {"public-read", "public-read-write", "authenticated-read"}
	msg := sprintf("aws_s3_bucket.%s: acl=%q は禁止です", [name, b.acl])
}

deny contains msg if {
	some name, blocks in input.resource.aws_s3_bucket_acl
	some a in blocks
	a.acl in {"public-read", "public-read-write", "authenticated-read"}
	msg := sprintf("aws_s3_bucket_acl.%s: acl=%q は禁止です", [name, a.acl])
}

# 3) 全ての S3 バケットに public_access_block を付ける。
deny contains msg if {
	some name, _ in input.resource.aws_s3_bucket
	not has_public_access_block(name)
	msg := sprintf("aws_s3_bucket.%s: aws_s3_bucket_public_access_block がありません", [name])
}

has_public_access_block(bucket_name) if {
	some _, blocks in input.resource.aws_s3_bucket_public_access_block
	some pab in blocks
	contains(pab.bucket, sprintf("aws_s3_bucket.%s.", [bucket_name]))
	pab.block_public_acls == true
	pab.block_public_policy == true
	pab.ignore_public_acls == true
	pab.restrict_public_buckets == true
}

# 4) IAM のワイルドカード権限は禁止。
deny contains msg if {
	some name, blocks in input.resource.aws_iam_policy
	some p in blocks
	doc := json.unmarshal(p.policy)
	some st in doc.Statement
	st.Effect == "Allow"
	wildcard_action(st.Action)
	st.Resource == "*"
	msg := sprintf("aws_iam_policy.%s: Action=* かつ Resource=* の許可は禁止です", [name])
}

wildcard_action(a) if a == "*"

wildcard_action(a) if {
	some x in a
	x == "*"
}
