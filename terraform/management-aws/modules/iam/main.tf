locals {
  roles = toset(["gitlab", "runner", "signoz"])
}

resource "aws_iam_policy" "ssm_session" {
  name        = "${var.name_prefix}-ssm-session"
  description = "Minimum permissions for Session Manager"
  policy      = data.aws_iam_policy_document.ssm_session.json
}

# roles and instance profiles

resource "aws_iam_role" "this" {
  for_each = local.roles

  name               = "${var.name_prefix}-${each.key}"
  description        = "Instance role for ${each.key}"
  assume_role_policy = data.aws_iam_policy_document.assume_ec2.json
}

resource "aws_iam_role_policy_attachment" "ssm_session" {
  for_each = local.roles

  role       = aws_iam_role.this[each.key].name
  policy_arn = aws_iam_policy.ssm_session.arn
}

resource "aws_iam_instance_profile" "this" {
  for_each = local.roles

  name = "${var.name_prefix}-${each.key}"
  role = aws_iam_role.this[each.key].name
}

resource "aws_iam_role_policy" "gitlab_secrets" {
  name   = "read-sync-secrets"
  role   = aws_iam_role.this["gitlab"].id
  policy = data.aws_iam_policy_document.gitlab_secrets.json
}