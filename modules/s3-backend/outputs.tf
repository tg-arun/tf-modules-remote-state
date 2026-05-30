output "state_bucket_name" {
  description = "S3 bucket name — paste this into your backend.tf files"
  value       = aws_s3_bucket.terraform_state.bucket
}

output "state_bucket_arn" {
  description = "ARN of the state bucket"
  value       = aws_s3_bucket.terraform_state.arn
}

output "dynamodb_table_name" {
  description = "DynamoDB table name — paste this into your backend.tf files"
  value       = aws_dynamodb_table.terraform_state_lock.name
}

output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB lock table"
  value       = aws_dynamodb_table.terraform_state_lock.arn
}

output "iam_policy_arn" {
  description = "Attach this policy to any IAM user or role that runs terraform apply"
  value       = aws_iam_policy.terraform_state_access.arn
}

# Ready-to-paste backend config block.
# After running bootstrap, copy this output directly into your backend.tf
output "backend_config" {
  description = "Copy this into your environments/*/backend.tf"
  value       = <<-EOT
    terraform {
      backend "s3" {
        bucket         = "${aws_s3_bucket.terraform_state.bucket}"
        key            = "ENV_NAME/COMPONENT/terraform.tfstate"
        region         = "${var.aws_region}"
        dynamodb_table = "${aws_dynamodb_table.terraform_state_lock.name}"
        encrypt        = true
      }
    }
  EOT
}