terraform {
  required_version = ">= 1.9"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# 学習用。実際には apply しない(guard-bash が deny、CI は validate と scan のみ)。
# 資格情報を一切要求しない設定にして、plan / validate をオフラインで通す。
provider "aws" {
  region                      = "ap-northeast-1"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  access_key                  = "mock" # allow-secret: 学習用のダミー。実 API は呼ばない
  secret_key                  = "mock" # allow-secret: 同上
}
