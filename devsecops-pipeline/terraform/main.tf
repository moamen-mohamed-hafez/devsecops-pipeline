# ============================================================
# Terraform — AWS Infrastructure
# This file contains INTENTIONAL misconfigurations to
# demonstrate tfsec catching real-world IaC security issues.
# The "after fix" version is in main.secure.tf (for reference)
# ============================================================

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # State backend — use S3 + DynamoDB in production
  # backend "s3" {
  #   bucket         = "your-terraform-state"
  #   key            = "devsecops/terraform.tfstate"
  #   region         = "eu-west-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-locks"
  # }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "eu-west-1"
}

variable "app_name" {
  description = "Application name"
  type        = string
  default     = "devsecops-demo"
}

# ─────────────────────────────────────────────────────────────
# ❌ VULNERABILITY 1: S3 bucket with no encryption
# tfsec rule: aws-s3-enable-bucket-encryption
# Fix: Add server_side_encryption_configuration block
# ─────────────────────────────────────────────────────────────
resource "aws_s3_bucket" "app_bucket" {
  bucket = "${var.app_name}-storage"

  tags = {
    Name        = "${var.app_name}-storage"
    Environment = "production"
  }
}

# ❌ VULNERABILITY 2: S3 bucket versioning disabled
# tfsec rule: aws-s3-enable-versioning
resource "aws_s3_bucket_versioning" "app_bucket" {
  bucket = aws_s3_bucket.app_bucket.id
  versioning_configuration {
    status = "Disabled"    # Should be "Enabled"
  }
}

# ❌ VULNERABILITY 3: S3 bucket public access NOT blocked
# tfsec rule: aws-s3-block-public-acls
# This means anyone on the internet could potentially access it
resource "aws_s3_bucket_public_access_block" "app_bucket" {
  bucket = aws_s3_bucket.app_bucket.id

  block_public_acls       = false   # Should be true
  block_public_policy     = false   # Should be true
  ignore_public_acls      = false   # Should be true
  restrict_public_buckets = false   # Should be true
}

# ─────────────────────────────────────────────────────────────
# ❌ VULNERABILITY 4: Security group open to the world
# tfsec rule: aws-ec2-no-public-ingress-sgr
# Port 22 (SSH) and 3000 open to 0.0.0.0/0 — anyone can connect
# ─────────────────────────────────────────────────────────────
resource "aws_security_group" "app_sg" {
  name        = "${var.app_name}-sg"
  description = "Security group for app"

  # ❌ SSH open to the entire internet
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]    # Should be your office IP
  }

  # ❌ App port open to the entire internet without restriction
  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.app_name}-sg"
  }
}

# ─────────────────────────────────────────────────────────────
# ❌ VULNERABILITY 5: RDS without encryption at rest
# tfsec rule: aws-rds-encrypt-instance-storage-data
# ─────────────────────────────────────────────────────────────
resource "aws_db_instance" "app_db" {
  identifier        = "${var.app_name}-db"
  engine            = "postgres"
  engine_version    = "15.4"
  instance_class    = "db.t3.micro"
  allocated_storage = 20
  db_name           = "appdb"
  username          = "admin"
  password          = "changeme123"   # ❌ Hardcoded password — use Secrets Manager

  storage_encrypted       = false    # ❌ Should be true
  backup_retention_period = 0        # ❌ Should be at least 7 (days)
  deletion_protection     = false    # ❌ Should be true in production
  skip_final_snapshot     = true     # ❌ Should be false in production
  publicly_accessible     = true     # ❌ Should be false

  tags = {
    Name = "${var.app_name}-db"
  }
}

# ─────────────────────────────────────────────────────────────
# ❌ VULNERABILITY 6: CloudWatch logs not encrypted
# tfsec rule: aws-cloudwatch-log-group-customer-key
# ─────────────────────────────────────────────────────────────
resource "aws_cloudwatch_log_group" "app_logs" {
  name              = "/aws/app/${var.app_name}"
  retention_in_days = 1    # ❌ Too short — should be 30-90 days minimum
  # kms_key_id = ""        # ❌ Missing — logs stored unencrypted
}
