variable "project_name" {
  description = "Project name — used in bucket and table naming"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{3,32}$", var.project_name))
    error_message = "project_name must be 3-32 lowercase alphanumeric characters or hyphens."
  }
}

variable "aws_region" {
  description = "AWS region where the S3 bucket and DynamoDB table will be created"
  type        = string
  default     = "ap-south-1"
}

variable "aws_account_id" {
  description = "Your 12-digit AWS account ID — used to make the bucket name globally unique"
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id must be exactly 12 digits."
  }
}

variable "log_retention_days" {
  description = "How many days to keep S3 access logs"
  type        = number
  default     = 90
}