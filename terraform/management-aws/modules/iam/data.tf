data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

# EC2 is the only service allowed to assume these roles

data "aws_iam_policy_document" "assume_ec2" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# Used instead of the AmazonSSMManagedInstanceCore managed policy

data "aws_iam_policy_document" "ssm_session" {
  statement {
    sid = "SessionManager"
    actions = [
      "ssm:UpdateInstanceInformation",
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
    ]
    resources = ["*"]
  }
}

# gitlab: read only the repo sync secrets (GitHub deploy key, GitLab token)

data "aws_iam_policy_document" "gitlab_secrets" {
  statement {
    sid       = "ReadSyncSecrets"
    actions   = ["ssm:GetParameter"]
    resources = ["arn:${data.aws_partition.current.partition}:ssm:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:parameter${var.gitlab_secrets_path}/*"]
  }

  # only needed when the parameters are encrypted with a customer managed key
  dynamic "statement" {
    for_each = var.kms_key_arn == null ? [] : [var.kms_key_arn]

    content {
      sid       = "DecryptSyncSecrets"
      actions   = ["kms:Decrypt"]
      resources = [statement.value]
    }
  }
}