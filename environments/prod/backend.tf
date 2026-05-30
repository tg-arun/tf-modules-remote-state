terraform {
  backend "s3" {
    bucket       = "tg-project-tfstate-939139585771"
    key          = "prod/vpc/terraform.tfstate" # different key from dev
    region       = "ap-south-1"
    use_lockfile = true
    encrypt      = true
  }
}