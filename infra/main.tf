provider "aws" {
  region = "us-east-1"
}

# Public S3 bucket (insecure)
resource "aws_s3_bucket" "public_bucket" {
  bucket = "demo-insecure-bucket-please-change"
  acl    = "public-read"
}

# Security group allowing all inbound traffic
resource "aws_security_group" "insecure_sg" {
  name        = "insecure-sg"
  description = "Allow all inbound"

  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# IAM user with wide-open permissions
resource "aws_iam_user" "bad_user" {
  name = "baduser"
}

resource "aws_iam_user_policy" "bad_policy" {
  name   = "baduser_policy"
  user   = aws_iam_user.bad_user.name
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "*",
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
EOF
}
