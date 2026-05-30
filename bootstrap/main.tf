terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  # No backend block — local state is intentional for bootstrap
}

provider "aws" {
  region = var.aws_region
}

module "s3_backend" {
  source = "../modules/s3-backend"

  project_name   = var.project_name
  aws_region     = var.aws_region
  aws_account_id = var.aws_account_id
}

# Print everything you need for the next steps
output "state_bucket_name" {
  value = module.s3_backend.state_bucket_name
}

output "dynamodb_table_name" {
  value = module.s3_backend.dynamodb_table_name
}

output "backend_config" {
  value = module.s3_backend.backend_config
}