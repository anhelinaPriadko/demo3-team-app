locals {
  instances = {
    nginx     = module.nginx
    app       = module.app
    db_master = module.db_master
    db_slave  = module.db_slave
  }
}

output "instance_names" {
  description = "Instance names, used to connect through IAP"
  value       = { for name, m in local.instances : name => m.name }
}

output "private_ips" {
  description = "Internal IP address of each instance"
  value       = { for name, m in local.instances : name => m.private_ip }
}

output "nginx_public_ip" {
  description = "Static public IP of Nginx (for the Pingdom check and DNS)"
  value       = module.nginx.public_ip
}

output "iap_ssh_commands" {
  description = "Ready-to-run IAP SSH commands"
  value = {
    for name, m in local.instances :
    name => "gcloud compute ssh ${m.name} --zone ${var.zone} --project ${var.project_id} --tunnel-through-iap"
  }
}

output "bucket_name" {
  description = "Name of the application bucket"
  value       = module.storage.bucket_name
}

# Used by the vpn root later (through terraform_remote_state)

output "project_id" {
  description = "GCP project ID"
  value       = var.project_id
}

output "region" {
  description = "GCP region"
  value       = var.region
}

output "network_name" {
  description = "Name of the application VPC"
  value       = module.network.network_name
}

output "network_self_link" {
  description = "Self link of the application VPC"
  value       = module.network.network_self_link
}

output "public_subnet_cidr" {
  description = "CIDR of the public subnet"
  value       = module.network.public_subnet_cidr
}

output "private_subnet_cidr" {
  description = "CIDR of the private subnet"
  value       = module.network.private_subnet_cidr
}
