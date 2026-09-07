# Reading Shelf の(仮想的な)デプロイ先。OG 画像のキャッシュ用バケットと API 用のセキュリティグループ。
# 「安全な既定」を全部明示している。演習では 1 つずつ外して、どのツールが何を検出するかを見る。

variable "project" {
  type    = string
  default = "reading-shelf"
}

variable "vpc_id" {
  type    = string
  default = "vpc-00000000000000000"
}

resource "aws_kms_key" "cache" {
  description         = "${var.project} cache bucket"
  enable_key_rotation = true
}

resource "aws_s3_bucket" "cache" {
  bucket = "${var.project}-og-cache"
}

resource "aws_s3_bucket_public_access_block" "cache" {
  bucket                  = aws_s3_bucket.cache.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "cache" {
  bucket = aws_s3_bucket.cache.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cache" {
  bucket = aws_s3_bucket.cache.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.cache.arn
    }
  }
}

resource "aws_s3_bucket_logging" "cache" {
  bucket        = aws_s3_bucket.cache.id
  target_bucket = aws_s3_bucket.cache.id
  target_prefix = "access-logs/"
}

resource "aws_security_group" "api" {
  name        = "${var.project}-api"
  description = "API: allow HTTPS from the load balancer only"
  vpc_id      = var.vpc_id

  ingress {
    description     = "HTTPS from ALB"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # enricher の外部 URL 取得と registry 到達に必要。宛先を絞れないため受容し、理由を残す(Exercise 06)。
  #trivy:ignore:AVD-AWS-0104
  egress {
    description = "HTTPS to the internet (enricher fetch, package registries)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "alb" {
  name        = "${var.project}-alb"
  description = "ALB: public HTTPS"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTPS from the internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "to API"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }
}
