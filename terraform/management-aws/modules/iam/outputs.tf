output "gitlab_instance_profile" {
  description = "Instance profile name for the GitLab server"
  value       = aws_iam_instance_profile.this["gitlab"].name
}

output "runner_instance_profile" {
  description = "Instance profile name for the GitLab runners"
  value       = aws_iam_instance_profile.this["runner"].name
}

output "signoz_instance_profile" {
  description = "Instance profile name for SigNoz"
  value       = aws_iam_instance_profile.this["signoz"].name
}

output "role_names" {
  description = "Role names by instance, for attaching extra policies later"
  value       = { for k, r in aws_iam_role.this : k => r.name }
}
