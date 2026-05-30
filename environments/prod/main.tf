terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = "prod"
      ManagedBy   = "Terraform"
    }
  }
}

# Same module, different values — this is the power of modules
module "vpc" {
  source = "../../modules/vpc"

  project_name       = var.project_name
  environment        = "prod"
  vpc_cidr           = var.vpc_cidr
  az_count           = 3              # 3 AZs for high availability in prod
  enable_nat_gateway = true           # prod needs private subnet internet access
}