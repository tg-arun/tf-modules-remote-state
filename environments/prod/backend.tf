terraform {
  backend "s3" {
    bucket         = "BUCKET_NAME_FROM_BOOTSTRAP_OUTPUT"
    key            = "prod/vpc/terraform.tfstate"  # different key from dev
    region         = "ap-south-1"
    dynamodb_table = "myproject-terraform-state-lock"
    encrypt        = true
  }
}