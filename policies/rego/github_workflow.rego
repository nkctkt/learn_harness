# GitHub Actions ワークフローの組織ポリシー。汎用スキャナ(actionlint / zizmor)ではなく「うちの決め事」を書く場所。
#   conftest test --policy policies/rego --namespace github_workflow .github/workflows/*.yml
package github_workflow

import rego.v1

# 1) 外部 action は 40 桁の commit SHA で固定する(tag は差し替え可能。CVE-2025-30066)。
#    同一リポジトリ内の ./ 参照と docker:// は対象外。
deny contains msg if {
	some job_name, job in input.jobs
	some step in job.steps
	uses := step.uses
	not startswith(uses, "./")
	not startswith(uses, "docker://")
	not regex.match(`^[^@]+@[0-9a-f]{40}(\s*#.*)?$`, uses)
	msg := sprintf("job %q: action %q は commit SHA で固定してください", [job_name, uses])
}

# 2) pull_request_target は fork の PR に write 権限と secrets を渡しうる。使わない。
deny contains msg if {
	input.on.pull_request_target
	msg := "pull_request_target は禁止です。pull_request を使い、必要なら workflow_run で分離してください"
}

deny contains msg if {
	some trigger in input.on
	trigger == "pull_request_target"
	msg := "pull_request_target は禁止です。pull_request を使い、必要なら workflow_run で分離してください"
}

# 3) トップレベルで permissions を宣言し、最小権限にする。write-all は禁止。
deny contains msg if {
	not input.permissions
	msg := "トップレベルの permissions が未宣言です(既定は広すぎる)。contents: read から始めてください"
}

deny contains msg if {
	input.permissions == "write-all"
	msg := "permissions: write-all は禁止です"
}

# 4) run ステップに ${{ github.event.* }} 等の信頼できない入力を直接展開しない(script injection)。
untrusted_prefixes := [
	"github.event.issue.title", "github.event.issue.body",
	"github.event.pull_request.title", "github.event.pull_request.body",
	"github.event.comment.body", "github.event.review.body",
	"github.head_ref", "github.event.pull_request.head.ref",
	"github.event.pull_request.head.label", "github.event.commits",
]

deny contains msg if {
	some job_name, job in input.jobs
	some step in job.steps
	run := step.run
	some prefix in untrusted_prefixes
	contains(run, sprintf("${{ %s", [prefix]))
	msg := sprintf("job %q: run で %q を直接展開しています(script injection)。env 経由で渡してください", [job_name, prefix])
}
