variable "aws_region" {
  description = "AWS region to create the state bucket and DynamoDB table"
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Project name used in bucket and table naming"
  type        = string
}

variable "aws_account_id" {
  description = "Your 12-digit AWS account ID"
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id must be exactly 12 digits."
  }
}
