output "gitlab_sg_id" {
  description = "ID of the GitLab server security group"
  value       = aws_security_group.gitlab.id
}

output "runner_sg_id" {
  description = "ID of the GitLab runners security group"
  value       = aws_security_group.runner.id
}

output "signoz_sg_id" {
  description = "ID of the SigNoz security group"
  value       = aws_security_group.signoz.id
}
