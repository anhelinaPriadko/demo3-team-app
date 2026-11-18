locals {
  instances = {
    gitlab = module.gitlab
    signoz = module.signoz
    runner = module.runner
  }
}

output "instance_ids" {
  description = "Instance IDs, used to connect with Session Manager"
  value       = { for name, m in local.instances : name => m.instance_id }
}

output "private_ips" {
  description = "Private IP address of each instance"
  value       = { for name, m in local.instances : name => m.private_ip }
}

output "ssm_commands" {
  description = "Ready-to-run Session Manager commands"
  value = {
    for name, m in local.instances :
    name => "aws ssm start-session --target ${m.instance_id} --region ${var.aws_region}"
  }
}

output "nat_public_ip" {
  description = "Public IP all outbound traffic comes from (for allowlisting)"
  value       = module.network.nat_public_ip
}

# Used by the vpn root later (through terraform_remote_state)

output "vpc_id" {
  description = "ID of the management VPC"
  value       = module.network.vpc_id
}

output "vpc_cidr" {
  description = "CIDR block of the management VPC"
  value       = module.network.vpc_cidr
}

output "private_route_table_id" {
  description = "ID of the private route table, where the route to GCP is added over the VPN"
  value       = module.network.private_route_table_id
}
