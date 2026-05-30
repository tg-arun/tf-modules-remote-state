# This tells Terraform to store dev state in S3
# Replace BUCKET_NAME with your bootstrap output
terraform {
  backend "s3" {
    bucket         = "tg-project-tfstate-939139585771"
    key            = "dev/vpc/terraform.tfstate"
    region         = "ap-south-1"
    use_lockfile   = true
    encrypt        = true
  }
}