# ──────────────────────────────────────────────
# S3 bucket — stores all Terraform state files
# ──────────────────────────────────────────────

resource "aws_s3_bucket" "terraform_state" {
  # Bucket name includes account ID to guarantee global uniqueness.
  # S3 bucket names are global across ALL AWS accounts worldwide.
  bucket = "${var.project_name}-tfstate-${var.aws_account_id}"

  # CRITICAL: prevent_destroy stops anyone accidentally running
  # terraform destroy on this bucket. If your state bucket is deleted,
  # you lose the record of all your infrastructure. This is a hard stop.
  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name    = "${var.project_name}-terraform-state"
    Purpose = "Terraform remote state storage"
  }
}

# ── Versioning ────────────────────────────────
# Every time terraform apply runs, a new version of the state
# file is saved. If a bad apply corrupts state, you can restore
# the previous version from S3 version history.
resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# ── Encryption ────────────────────────────────
# State files can contain sensitive data — subnet IDs, resource ARNs,
# sometimes even passwords if you're not careful.
# AES256 encrypts every object at rest automatically.
resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true  # reduces KMS API calls and cost
  }
}

# ── Block all public access ───────────────────
# State files must NEVER be public. This setting overrides any
# bucket policy or ACL that tries to make objects public.
resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ── Lifecycle rule ────────────────────────────
# Old state versions accumulate over time. This rule keeps the
# last 90 days of versions and deletes older ones automatically.
# Prevents the bucket growing indefinitely and saves storage cost.
resource "aws_s3_bucket_lifecycle_configuration" "terraform_state" {
  # Must wait for versioning to be enabled first
  depends_on = [aws_s3_bucket_versioning.terraform_state]

  bucket = aws_s3_bucket.terraform_state.id

  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"
     
    filter {}
    
    # Only applies to old (non-current) versions
    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    # Clean up incomplete multipart uploads after 7 days
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# ──────────────────────────────────────────────
# DynamoDB table — state locking
# ──────────────────────────────────────────────
# When terraform apply starts, it writes a lock entry to this table.
# Any other apply running at the same time will see the lock and fail
# with: "Error acquiring the state lock"
# When apply finishes, the lock is released automatically.
#
# Without this: two engineers apply at the same time → state corruption
# With this: second engineer gets a clear error and waits

resource "aws_dynamodb_table" "terraform_state_lock" {
  name         = "${var.project_name}-tfstate-lock"
  billing_mode = "PAY_PER_REQUEST"  # no capacity planning, scales automatically
  hash_key     = "LockID"           # Terraform requires exactly this field name

  attribute {
    name = "LockID"
    type = "S"  # S = String
  }

  # Protect the lock table from accidental deletion too
  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name    = "${var.project_name}-terraform-state-lock"
    Purpose = "Terraform state locking"
  }
}

# ──────────────────────────────────────────────
# IAM policy — who can use this backend
# ──────────────────────────────────────────────
# Attach this policy to any IAM user or role that needs to
# run terraform apply. Without these permissions, Terraform
# can't read or write state.

resource "aws_iam_policy" "terraform_state_access" {
  name        = "${var.project_name}-terraform-state-access"
  description = "Allows Terraform to read/write state in S3 and lock in DynamoDB"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3StateAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketVersioning"
        ]
        Resource = [
          aws_s3_bucket.terraform_state.arn,
          "${aws_s3_bucket.terraform_state.arn}/*"
        ]
      },
      {
        Sid    = "DynamoDBLockAccess"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem",
          "dynamodb:DescribeTable"
        ]
        Resource = aws_dynamodb_table.terraform_state_lock.arn
      }
    ]
  })
}