# Provision ECR and Fargate resources
resource "aws_ecr_repository" "gotest" {
  name = "gotest"
  force_delete = true
  tags = {
    Name = "gotest"
  }
}

# IAM Policy for ECR Push Only
resource "aws_iam_policy" "ecr_push_only" {
  name        = "ECRPushOnlyPolicy"
  description = "Policy that allows pushing images to ECR only"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer"
        ]
        Resource = aws_ecr_repository.gotest.arn
      }
    ]
  })
}

# IAM User for ECR Push Only
resource "aws_iam_user" "ecr_push_only" {
  name = "ecr-push-only"
  force_destroy = true
}

# Attach the policy to the user
resource "aws_iam_user_policy_attachment" "ecr_push_only" {
  user       = aws_iam_user.ecr_push_only.name
  policy_arn = aws_iam_policy.ecr_push_only.arn
}

resource "aws_iam_access_key" "ecr_push_only" {
  user = aws_iam_user.ecr_push_only.name
}
