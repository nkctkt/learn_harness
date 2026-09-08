---
paths:
  - "infra/**"
  - "**/Dockerfile"
---

# infra(Docker / Terraform)

- Terraform は `validate` と scan まで。`apply` / `destroy` は Agent からは実行できない(HITL-5、guard-bash + permissions.deny)。
- Dockerfile は multi-stage、非 root、`--ignore-scripts`、ベース image はタグ + digest。Rego(`policies/rego/terraform.rego`)と Trivy config が HIGH 以上を落とす。
- compose(`infra/docker/compose.yaml`)は 4 サービスの結合確認用。CI では docker build + Trivy image のみ(結合は契約テストで代替)。
- IaC の変更は CODEOWNERS 承認(HITL-4)。intent.md の「触れる信頼境界」に infra を書く。
