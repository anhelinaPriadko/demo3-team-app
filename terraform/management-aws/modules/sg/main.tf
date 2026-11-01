locals {
  otlp_source_cidrs = toset(concat([var.vpc_cidr], var.additional_otlp_cidrs))
}

# security groups

resource "aws_security_group" "gitlab" {
  name        = "demo3-gitlab-sg"
  description = "GitLab server and repository sync"
  vpc_id      = var.vpc_id

  tags = {
    Name = "demo3-gitlab-sg"
  }
}

resource "aws_security_group" "runner" {
  name        = "demo3-runner-sg"
  description = "GitLab runners"
  vpc_id      = var.vpc_id

  tags = {
    Name = "demo3-runner-sg"
  }
}

resource "aws_security_group" "signoz" {
  name        = "demo3-signoz-sg"
  description = "SigNoz"
  vpc_id      = var.vpc_id

  tags = {
    Name = "demo3-signoz-sg"
  }
}

# gitlab-sg: ingress

resource "aws_vpc_security_group_ingress_rule" "gitlab_https_from_runner" {
  security_group_id            = aws_security_group.gitlab.id
  referenced_security_group_id = aws_security_group.runner.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  description                  = "Runners clone code and report job results"
}

# gitlab-sg: egress
# All outbound for now (repo sync over SSH, SSM, AWS APIs, package repos).
# Narrow to TCP 22 and 443 once everything works.

resource "aws_vpc_security_group_egress_rule" "gitlab_all" {
  security_group_id = aws_security_group.gitlab.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "All outbound"
}

# runner-sg: no ingress, runners poll GitLab and accept no inbound traffic

resource "aws_vpc_security_group_egress_rule" "runner_all" {
  security_group_id = aws_security_group.runner.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "All outbound"
}

# signoz-sg: OTLP in from the VPC, plus any extra CIDRs (e.g. GCP after the VPN)
# The UI has no rule on purpose: reach it with SSM port forwarding.

resource "aws_vpc_security_group_ingress_rule" "signoz_otlp_grpc" {
  for_each = local.otlp_source_cidrs

  security_group_id = aws_security_group.signoz.id
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 4317
  to_port           = 4317
  description       = "OTLP gRPC"
}

resource "aws_vpc_security_group_ingress_rule" "signoz_otlp_http" {
  for_each = local.otlp_source_cidrs

  security_group_id = aws_security_group.signoz.id
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 4318
  to_port           = 4318
  description       = "OTLP HTTP"
}

resource "aws_vpc_security_group_egress_rule" "signoz_all" {
  security_group_id = aws_security_group.signoz.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "All outbound"
}
